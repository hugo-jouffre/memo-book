import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
import { JOB_NAMES } from "../src/jobs/queue.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Les routes d'un souvenir que la conversation n'appelle pas : la relance de
 * la rédaction (`POST /v1/entries/:id/redaction`).
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
  vi.restoreAllMocks();
});

afterAll(async () => {
  await harness?.close();
});

describe("relancer la rédaction", () => {
  it("ne met qu'une rédaction en file, même touchée plusieurs fois", async () => {
    // Chaque relance est un appel d'IA payé : dix touches, une rédaction.
    const owner = await registerAccount(harness.app);
    const memo = await harness.prisma.memo.create({
      data: { ownerAccountId: owner.accountId, title: "Rome 2026", accessCode: "REDAC1", stage: "ongoing" },
    });
    const entry = await harness.prisma.entry.create({
      data: {
        memoId: memo.id,
        kind: "text",
        status: "ready",
        redactionStatus: "ready",
        transcript: "Le Colisée au petit matin.",
        capturedAt: new Date(),
      },
    });
    const publish = vi.spyOn(harness.context.queue, "publish").mockResolvedValue();

    const relaunch = () =>
      harness.app.inject({
        method: "POST",
        url: `/v1/entries/${entry.id}/redaction`,
        headers: { authorization: owner.authorization },
      });
    const responses = await Promise.all([relaunch(), relaunch(), relaunch()]);

    expect(responses.map((response) => response.statusCode).sort()).toEqual([200, 200, 202]);
    expect(publish.mock.calls.filter(([name]) => name === JOB_NAMES.redact)).toHaveLength(1);
    expect((await relaunch()).statusCode).toBe(200);
  });

  it("se relance après un échec", async () => {
    const owner = await registerAccount(harness.app);
    const memo = await harness.prisma.memo.create({
      data: { ownerAccountId: owner.accountId, title: "Rome 2026", accessCode: "REDAC2", stage: "ongoing" },
    });
    const entry = await harness.prisma.entry.create({
      data: {
        memoId: memo.id,
        kind: "text",
        status: "ready",
        redactionStatus: "failed",
        transcript: "La fontaine de Trevi.",
        capturedAt: new Date(),
      },
    });
    vi.spyOn(harness.context.queue, "publish").mockResolvedValue();

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/entries/${entry.id}/redaction`,
      headers: { authorization: owner.authorization },
    });

    expect(response.statusCode).toBe(202);
    expect((await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } })).redactionStatus).toBe(
      "pending",
    );
  });
});
