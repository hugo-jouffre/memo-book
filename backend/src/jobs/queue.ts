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

  constructor(connectionString: string) {
    this.boss = new PgBoss({
      connectionString,
      retryLimit: 3,
      retryDelay: 30,
      retryBackoff: true,
      /**
       * ⚠️ **pg-boss ouvre son propre pool, en plus de celui de Prisma.**
       *
       * Le `connection_limit` posé sur l'URL ne le concerne pas : il vaut pour
       * le client Prisma, pas pour cette bibliothèque, qui prend 10 connexions
       * par défaut. Or le pooler Supabase en **mode session** n'en accorde que
       * **15 au total** — et il les compte par serveur, pas par pool.
       *
       * 5 (Prisma) + 10 (ici) = pile la limite : le premier script lancé à côté
       * fait basculer tout le serveur en « Erreur interne du serveur », et la
       * cause est invisible depuis la route qui échoue. Quatre laisse de la
       * place au worker et aux scripts de vérification.
       *
       * C'est bas parce que la file est peu chargée : les jobs sont longs
       * (transcription, rédaction, PDF) et rares, pas courts et nombreux.
       */
      max: 4,
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
