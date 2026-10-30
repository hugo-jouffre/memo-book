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

/**
 * **Supprimer un souvenir efface son fichier** (Hugo, 19/10/2026, QA D12) :
 * le vocal ou la photo ne reste pas en stockage, rattaché à rien.
 */
/**
 * **Garder la transcription littérale** (Hugo, 28/10/2026). La fiche montre
 * les deux versions ; ce drapeau dit laquelle part au carnet.
 */
describe("choisir entre la littérale et le texte rédigé", () => {
  async function redactedEntry(code: string) {
    const owner = await registerAccount(harness.app);
    const memo = await harness.prisma.memo.create({
      data: { ownerAccountId: owner.accountId, title: "Rome 2026", accessCode: code, stage: "ongoing" },
    });
    const entry = await harness.prisma.entry.create({
      data: {
        memoId: memo.id,
        kind: "audio",
        status: "ready",
        redactionStatus: "ready",
        transcript: "euh donc le Colisée au petit matin voilà",
        redactedText: "Le Colisée au petit matin.",
        capturedAt: new Date(),
      },
    });
    return { owner, memo, entry };
  }

  it("garde la littérale, et ça ne coûte aucune correction", async () => {
    const { owner, entry } = await redactedEntry("LITT01");

    const response = await harness.app.inject({
      method: "PATCH",
      url: `/v1/entries/${entry.id}`,
      headers: { authorization: owner.authorization },
      payload: { prefersTranscript: true },
    });

    expect(response.statusCode).toBe(200);
    const body = response.json<{ displayText: string; prefersTranscript: boolean }>();
    expect(body.prefersTranscript).toBe(true);
    // C'est elle qui part au carnet : `finalTextOf` le dit à toute la chaîne.
    expect(body.displayText).toBe("euh donc le Colisée au petit matin voilà");

    // Ce n'est pas une correction au clavier : le pot des 200 caractères
    // offerts n'est pas entamé.
    const saved = await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } });
    expect(saved.correctionFreeCharacters).toBe(0);
    expect(saved.editedText).toBeNull();
  });

  it("revient au texte rédigé", async () => {
    const { owner, entry } = await redactedEntry("LITT02");
    const patch = (prefersTranscript: boolean) =>
      harness.app.inject({
        method: "PATCH",
        url: `/v1/entries/${entry.id}`,
        headers: { authorization: owner.authorization },
        payload: { prefersTranscript },
      });

    await patch(true);
    const back = await patch(false);

    expect(back.json<{ displayText: string }>().displayText).toBe("Le Colisée au petit matin.");
  });

  it("une correction au clavier passe devant le choix", async () => {
    const { owner, entry } = await redactedEntry("LITT03");

    await harness.app.inject({
      method: "PATCH",
      url: `/v1/entries/${entry.id}`,
      headers: { authorization: owner.authorization },
      payload: { prefersTranscript: true },
    });
    const corrected = await harness.app.inject({
      method: "PATCH",
      url: `/v1/entries/${entry.id}`,
      headers: { authorization: owner.authorization },
      payload: { editedText: "Le Colisée, au tout petit matin." },
    });

    expect(corrected.json<{ displayText: string }>().displayText).toBe("Le Colisée, au tout petit matin.");
  });

  /**
   * Redemander une rédaction, c'est vouloir la lire : sans ça, la nouvelle
   * version arrivait dans une fiche qui continuait d'imprimer le brut.
   */
  it("relancer l'analyse fait tomber le choix", async () => {
    const { owner, entry } = await redactedEntry("LITT04");
    vi.spyOn(harness.context.queue, "publish").mockResolvedValue();

    await harness.app.inject({
      method: "PATCH",
      url: `/v1/entries/${entry.id}`,
      headers: { authorization: owner.authorization },
      payload: { prefersTranscript: true },
    });
    const relaunched = await harness.app.inject({
      method: "POST",
      url: `/v1/entries/${entry.id}/redaction`,
      headers: { authorization: owner.authorization },
    });

    expect(relaunched.statusCode).toBe(202);
    const saved = await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } });
    expect(saved.prefersTranscript).toBe(false);
  });
});

describe("supprimer un souvenir", () => {
  it("efface la ligne du média et son fichier, mais pas un fichier qu'un autre souvenir garde", async () => {
    const owner = await registerAccount(harness.app);
    const memo = await harness.prisma.memo.create({
      data: { ownerAccountId: owner.accountId, title: "Rome 2026", accessCode: "SUPPR1", stage: "ongoing" },
    });
    const stored = await harness.context.storage.put("photo", "a.jpg", Buffer.from("a"), "image/jpeg");
    const entry = await harness.prisma.entry.create({
      data: {
        memo: { connect: { id: memo.id } },
        kind: "photo",
        status: "ready",
        capturedAt: new Date(),
        media: { create: { storageKey: stored.storageKey, mimeType: "image/jpeg", bytes: 1 } },
      },
      include: { media: true },
    });
    // Un second souvenir sur un même média partagé.
    const shared = await harness.context.storage.put("photo", "b.jpg", Buffer.from("b"), "image/jpeg");
    const first = await harness.prisma.entry.create({
      data: {
        memo: { connect: { id: memo.id } },
        kind: "photo",
        status: "ready",
        capturedAt: new Date(),
        media: { create: { storageKey: shared.storageKey, mimeType: "image/jpeg", bytes: 1 } },
      },
    });
    const second = await harness.prisma.entry.create({
      data: { memoId: memo.id, kind: "photo", status: "ready", capturedAt: new Date(), mediaId: first.mediaId },
    });
    const remove = vi.spyOn(harness.context.storage, "remove");
    const destroy = (id: string) =>
      harness.app.inject({
        method: "DELETE",
        url: `/v1/entries/${id}`,
        headers: { authorization: owner.authorization },
      });

    expect((await destroy(entry.id)).statusCode).toBe(204);
    expect(await harness.prisma.mediaAsset.findUnique({ where: { id: entry.mediaId! } })).toBeNull();
    expect(remove).toHaveBeenCalledWith([stored.storageKey]);
    await expect(harness.context.storage.get(stored.storageKey)).rejects.toThrow();

    // Le média partagé reste tant qu'un souvenir le nomme…
    remove.mockClear();
    expect((await destroy(first.id)).statusCode).toBe(204);
    expect(remove).not.toHaveBeenCalled();
    expect(await harness.context.storage.get(shared.storageKey)).toEqual(Buffer.from("b"));
    // … et part avec le dernier.
    expect((await destroy(second.id)).statusCode).toBe(204);
    expect(remove).toHaveBeenCalledWith([shared.storageKey]);
  });

  it("une panne du stockage ne fait pas échouer la suppression", async () => {
    const owner = await registerAccount(harness.app);
    const memo = await harness.prisma.memo.create({
      data: { ownerAccountId: owner.accountId, title: "Rome 2026", accessCode: "SUPPR2", stage: "ongoing" },
    });
    const stored = await harness.context.storage.put("audio", "v.m4a", Buffer.from("v"), "audio/mp4");
    const entry = await harness.prisma.entry.create({
      data: {
        memo: { connect: { id: memo.id } },
        kind: "audio",
        status: "ready",
        capturedAt: new Date(),
        media: { create: { storageKey: stored.storageKey, mimeType: "audio/mp4", bytes: 1 } },
      },
    });
    vi.spyOn(harness.context.storage, "remove").mockRejectedValue(new Error("S3 en panne"));

    const response = await harness.app.inject({
      method: "DELETE",
      url: `/v1/entries/${entry.id}`,
      headers: { authorization: owner.authorization },
    });

    expect(response.statusCode).toBe(204);
    expect(await harness.prisma.entry.findUnique({ where: { id: entry.id } })).toBeNull();
    expect(await harness.prisma.mediaAsset.findUnique({ where: { id: entry.mediaId! } })).toBeNull();
  });
});
