import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { startQueueWhenPossible, type JobQueue } from "../src/jobs/queue.js";

/**
 * Ce que garantit `startQueueWhenPossible`, et pourquoi ça compte : **une base
 * indisponible ne doit plus emporter l'API**.
 *
 * Le serveur attendait la file avant d'ouvrir son port. Un pooler plein
 * remontait donc jusqu'à `main().catch`, qui sortait en code 1 — et `tsx watch`
 * ne relançant pas un process mort, le serveur de développement restait éteint
 * en silence. Ces trois cas tiennent la promesse inverse.
 */

/** Une file qui refuse de démarrer les *n* premières fois. */
function reluctantQueue(failures: number): JobQueue & { attempts: number } {
  const queue: JobQueue & { attempts: number } = {
    attempts: 0,
    register: (): void => {},
    publish: async (): Promise<void> => {},
    schedule: async (): Promise<void> => {},
    stop: async (): Promise<void> => {},
    healthy: async (): Promise<boolean> => true,
    start: async (): Promise<void> => {
      queue.attempts += 1;
      if (queue.attempts <= failures) {
        throw new Error("(EMAXCONNSESSION) max clients reached in session mode");
      }
    },
  };

  return queue;
}

const silent = { info: (): void => {}, error: (): void => {} };

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("startQueueWhenPossible", () => {
  it("ne rejette pas quand la file refuse de démarrer", async () => {
    const queue = reluctantQueue(Number.POSITIVE_INFINITY);

    // Aucun `await` : l'appelant n'attend pas la file, c'est tout le propos.
    const handle = startQueueWhenPossible(queue, silent);
    await vi.advanceTimersByTimeAsync(10_000);

    expect(queue.attempts).toBeGreaterThan(1);
    handle.cancel();
  });

  it("retente jusqu'à ce que Postgres accepte", async () => {
    const queue = reluctantQueue(3);

    startQueueWhenPossible(queue, silent);
    // 2 s, puis 4, puis 8 : l'attente double à chaque échec.
    await vi.advanceTimersByTimeAsync(20_000);

    expect(queue.attempts).toBe(4);

    // Et elle s'arrête là : une file démarrée ne se redémarre pas en boucle.
    await vi.advanceTimersByTimeAsync(60_000);
    expect(queue.attempts).toBe(4);
  });

  it("s'arrête quand le serveur s'arrête", async () => {
    const queue = reluctantQueue(Number.POSITIVE_INFINITY);

    const handle = startQueueWhenPossible(queue, silent);
    await vi.advanceTimersByTimeAsync(3_000);
    const attemptsAtShutdown = queue.attempts;

    handle.cancel();
    await vi.advanceTimersByTimeAsync(60_000);

    expect(queue.attempts).toBe(attemptsAtShutdown);
  });

  it("nomme la cause au lieu de recracher l'erreur de pg-boss", async () => {
    const queue = reluctantQueue(Number.POSITIVE_INFINITY);
    const causes: string[] = [];

    const handle = startQueueWhenPossible(queue, {
      info: (): void => {},
      error: (details: object): void => {
        causes.push(String((details as { cause?: unknown }).cause));
      },
    });
    await vi.advanceTimersByTimeAsync(0);
    handle.cancel();

    expect(causes[0]).toContain("pooler Supabase est plein");
  });
});
