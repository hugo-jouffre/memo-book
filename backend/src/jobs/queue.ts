import PgBoss from "pg-boss";

export const JOB_NAMES = {
  transcribe: "memobook.transcribe",
  redact: "memobook.redact",
  structure: "memobook.structure",
  render: "memobook.render",
  /**
   * Le ménage des abonnements sans voyage. Le seul job **du calendrier** et non
   * d'un geste : un voyage se termine à une date, pas quand on ouvre l'app.
   */
  endSubscriptions: "memobook.end-subscriptions",
} as const;

export type JobName = (typeof JOB_NAMES)[keyof typeof JOB_NAMES];

export type JobHandler<T> = (payload: T) => Promise<void>;

/**
 * Abstraction minimale au-dessus de pg-boss. Elle existe pour que les tests et
 * le smoke puissent exécuter le pipeline en ligne, sans Postgres ni worker.
 */
export interface JobQueue {
  register<T extends object>(name: JobName, handler: JobHandler<T>): void;
  publish<T extends object>(name: JobName, payload: T): Promise<void>;

  /**
   * Fait revenir un job **à heure fixe**, indéfiniment.
   *
   * Idempotent : reposer la même expression sur le même nom remplace l'horaire
   * au lieu d'en ajouter un second. C'est ce qui permet de l'appeler à chaque
   * démarrage sans accumuler les répétitions.
   *
   * @param cron une expression cron à cinq champs, en UTC.
   */
  schedule(name: JobName, cron: string): Promise<void>;

  start(): Promise<void>;
  stop(): Promise<void>;
  healthy(): Promise<boolean>;
}

/** File d'attente durable, adossée à Postgres — pas de Redis à opérer. */
export class PgBossQueue implements JobQueue {
  private readonly boss: PgBoss;
  private readonly handlers = new Map<JobName, JobHandler<never>>();
  private started = false;

  constructor(connectionString: string, options: { maxConnections?: number } = {}) {
    this.boss = new PgBoss({
      connectionString,
      /**
       * ⚠️ **pg-boss ouvre son propre pool, en plus de celui de Prisma.**
       *
       * Le `connection_limit` posé sur l'URL ne le concerne pas : il vaut pour
       * le client Prisma, pas pour cette bibliothèque, qui prend **10**
       * connexions par défaut. Sur le pooler Supabase en mode session, c'est
       * les deux tiers du budget pour une file qui traite quelques jobs par
       * jour — `splitPoolBudget` en donne donc une part, et c'est elle qui
       * arrive ici.
       *
       * Ce budget se compte pour **trois** process, pas un : l'API déployée,
       * son worker, et le serveur de développement. Relevé le 15/09/2026, avant
       * que ce plafond n'existe : 15 sessions sur 15 prises, dont 8 par
       * pg-boss, aucun process local lancé — la production remplissait la
       * limite à elle seule.
       *
       * Deux suffisent : les jobs sont longs (transcription, rédaction, PDF) et
       * rares, et interroger la file toutes les deux secondes tient en quelques
       * millisecondes. Voir `docs/debogage.md` § 4.
       */
      max: options.maxConnections ?? 2,
      retryLimit: 3,
      retryDelay: 30,
      retryBackoff: true,
    });

    // ⚠️ **Sans ce gestionnaire, une panne de la file tue le serveur.**
    //
    // `PgBoss` est un `EventEmitter` : un événement `error` sans écouteur est
    // relancé par Node et termine le processus. Et il y en a — l'horloge des
    // tâches planifiées interroge Postgres en fond, donc le premier
    // « max clients reached in session mode » du pooler arrivait par là et
    // faisait tomber l'API entière, pour une panne qui ne concernait que la
    // file.
    //
    // On le journalise et on continue : pg-boss retente tout seul, et les
    // routes, elles, n'ont rien à voir là-dedans.
    this.boss.on("error", (error) => {
      this.onError?.(error);
    });
  }

  /**
   * Où partent les pannes de la file. Posé par le serveur pour qu'elles
   * atterrissent dans ses logs plutôt que dans le vide.
   */
  onError?: (error: unknown) => void;

  register<T extends object>(name: JobName, handler: JobHandler<T>): void {
    this.handlers.set(name, handler);
  }

  async publish<T extends object>(name: JobName, payload: T): Promise<void> {
    // Dit ce qui se passe plutôt que de laisser remonter l'erreur interne de
    // pg-boss : la file peut être encore en train de naître (voir
    // `startQueueWhenPossible`), et c'est un état d'attente, pas une panne.
    if (!this.started) {
      throw new Error(
        "La file de travaux n'a pas encore démarré. Réessaie dans un instant.",
      );
    }
    await this.boss.send(name, payload);
  }

  async schedule(name: JobName, cron: string): Promise<void> {
    // La file doit tourner : pg-boss écrit l'horaire dans sa propre table.
    // Poser un horaire avant `start()` échouerait silencieusement, et le job ne
    // serait jamais réveillé.
    if (!this.started) {
      this.pendingSchedules.set(name, cron);
      return;
    }
    await this.boss.createQueue(name);
    await this.boss.schedule(name, cron);
  }

  /** Les horaires demandés avant le démarrage, posés dès qu'il a lieu. */
  private readonly pendingSchedules = new Map<JobName, string>();

  async start(): Promise<void> {
    if (this.started) return;
    await this.boss.start();

    for (const [name, handler] of this.handlers) {
      await this.boss.createQueue(name);
      await this.boss.work(name, async ([job]) => {
        if (!job) return;
        await (handler as JobHandler<object>)(job.data as object);
      });
    }

    this.started = true;

    for (const [name, cron] of this.pendingSchedules) {
      await this.schedule(name, cron);
    }
    this.pendingSchedules.clear();
  }

  async stop(): Promise<void> {
    if (!this.started) return;
    await this.boss.stop({ graceful: true });
    this.started = false;
  }

  async healthy(): Promise<boolean> {
    try {
      // `getQueues` fait un aller-retour SQL : c'est un vrai test de liveness.
      await this.boss.getQueues();
      return true;
    } catch {
      return false;
    }
  }
}

/** De quoi journaliser, sans dépendre du contexte — qui, lui, dépend d'ici. */
interface QueueLogger {
  info(details: object, message: string): void;
  error(details: object, message: string): void;
}

/**
 * Démarre la file **sans jamais faire tomber l'appelant**, et retente tant que
 * Postgres la refuse.
 *
 * ⚠️ **C'est ce qui empêche une base indisponible d'emporter l'API.** Le
 * serveur attendait `queue.start()` *avant* d'ouvrir son port : un pooler plein
 * — quinze sessions, et un `prisma studio` oublié suffit — remontait jusqu'à
 * `main().catch`, qui sortait en code 1. `tsx watch`, lui, ne relance pas un
 * process mort : il attend une modification de fichier. Le serveur de
 * développement restait donc éteint **en silence**, et on le découvrait depuis
 * l'app, sur un « Connexion impossible » qui accusait le réseau.
 *
 * Or les routes n'ont pas besoin de la file : elles y *publient*, au plus. Le
 * port s'ouvre donc d'abord, la file se branche quand elle peut, et l'attente
 * se voit dans les logs comme dans `/health`.
 *
 * L'attente double à chaque échec, jusqu'à trente secondes : un pooler plein se
 * libère en minutes, pas en millisecondes, et marteler la base ne fait
 * qu'occuper la connexion qu'on attend.
 */
export function startQueueWhenPossible(
  queue: JobQueue,
  logger: QueueLogger,
): { cancel: () => void } {
  let cancelled = false;
  let delay = 2_000;

  const attempt = async (): Promise<void> => {
    if (cancelled) return;

    try {
      await queue.start();
      if (!cancelled) logger.info({}, "File de travaux démarrée.");
    } catch (error) {
      if (cancelled) return;

      logger.error(
        { err: error, nouvelEssaiDans: `${delay / 1_000} s`, cause: diagnose(error) },
        "La file de travaux n'a pas démarré — l'API répond quand même.",
      );

      // `unref` : ce minuteur ne doit pas retenir le process au moment de
      // s'arrêter. Il retente si le serveur est encore là, rien de plus.
      setTimeout(() => void attempt(), delay).unref();
      delay = Math.min(delay * 2, 30_000);
    }
  };

  void attempt();

  return {
    cancel: () => {
      cancelled = true;
    },
  };
}

/**
 * Traduit la panne en geste, dans la langue des logs. Même intention que
 * `APIError.developerDiagnosis` côté iOS : on ne devine pas une panne, on lit
 * une ligne qui dit quoi faire.
 */
function diagnose(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);

  if (message.includes("EMAXCONNSESSION") || message.includes("max clients reached")) {
    return (
      "Le pooler Supabase est plein — 15 sessions au total en mode session. " +
      "Un second serveur, un `prisma studio`, un script laissé ouvert : ferme " +
      "ce qui traîne, ou attends que les sessions expirent."
    );
  }
  if (message.includes("ECONNREFUSED") || message.includes("ENOTFOUND")) {
    return "Postgres est injoignable : vérifie DATABASE_URL, et que la base est debout.";
  }
  return "Postgres a refusé la file.";
}

/**
 * Exécution synchrone : `publish` appelle le handler et attend. Utilisée par les
 * tests et par `npm run smoke`, où l'ordonnancement asynchrone n'apporterait que
 * du flakiness.
 */
export class InlineQueue implements JobQueue {
  private readonly handlers = new Map<JobName, JobHandler<never>>();

  register<T extends object>(name: JobName, handler: JobHandler<T>): void {
    this.handlers.set(name, handler);
  }

  async publish<T extends object>(name: JobName, payload: T): Promise<void> {
    const handler = this.handlers.get(name);
    if (!handler) throw new Error(`Aucun handler enregistré pour le job ${name}.`);
    await (handler as JobHandler<object>)(payload);
  }

  /**
   * Sans effet : une file en ligne n'a pas d'horloge, et un test qui attendrait
   * demain n'est pas un test. Le job qui s'y planifie s'appelle directement.
   */
  async schedule(): Promise<void> {}

  async start(): Promise<void> {}
  async stop(): Promise<void> {}
  async healthy(): Promise<boolean> {
    return true;
  }
}
