import PgBoss from "pg-boss";

export const JOB_NAMES = {
  transcribe: "memobook.transcribe",
  structure: "memobook.structure",
  render: "memobook.render",
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
    });
  }

  register<T extends object>(name: JobName, handler: JobHandler<T>): void {
    this.handlers.set(name, handler);
  }

  async publish<T extends object>(name: JobName, payload: T): Promise<void> {
    await this.boss.send(name, payload);
  }

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

  async start(): Promise<void> {}
  async stop(): Promise<void> {}
  async healthy(): Promise<boolean> {
    return true;
  }
}
