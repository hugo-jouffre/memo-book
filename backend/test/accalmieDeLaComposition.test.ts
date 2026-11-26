import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";
import { STRUCTURE_TIMING, waitUntilSettled } from "../src/jobs/structure.js";
import {
  PHOTOS_VALIDATED,
  PHOTOS_VALIDATED_BEFORE_RETURN,
  SCRIPTED_ANSWERS,
  SUGGESTION_SETS,
} from "../src/services/conversationCopy.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **La composition de fond attend que le voyageur ait fini** (T307).
 *
 * « Rien ne force à dire que le carnet est prêt dès que l'étape est
 * enregistrée, mieux vaut laisser le temps d'ajouter un vocal ou des photos »
 * (Hugo, 08/11/2026).
 *
 * Avant, « Valider cette étape » lançait la composition dans la seconde. Le
 * voyageur enchaînait un second vocal, sa rédaction démarrait, et cette
 * composition-là attendait trois minutes pour **échouer** : « 2 souvenir(s)
 * sont encore en cours de rédaction. » Un carnet composé pour rien, un échec
 * affiché, et tout à relancer.
 *
 * Ces durées-ci sont posées à la milliseconde : l'accalmie réelle est de
 * quarante-cinq secondes, et un test ne la vit pas. C'est le **comportement**
 * qu'on tient — qui attend, qui n'attend pas, et ce qu'on rend au plafond.
 */

let harness: TestHarness;
const reel = { ...STRUCTURE_TIMING };

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
  STRUCTURE_TIMING.pollMs = 20;
  STRUCTURE_TIMING.settleQuietMs = 300;
  STRUCTURE_TIMING.redactionWaitMs = 3_000;
});

afterEach(() => {
  Object.assign(STRUCTURE_TIMING, reel);
});

afterAll(async () => {
  await harness?.close();
});

/** Un carnet avec un souvenir rédigé — le cas d'une étape qu'on vient de valider. */
async function carnetAvecUnSouvenir(): Promise<string> {
  const { authorization } = await registerAccount(harness.app);
  const created = await harness.app.inject({
    method: "POST",
    url: "/v1/memos",
    headers: { authorization },
    payload: { title: "Grèce 2026", authors: "Maxime", theme: "voyage" },
  });
  expect(created.statusCode).toBe(201);
  const memoId = created.json<{ id: string }>().id;

  const entry = await harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memoId}/entries`,
    headers: { authorization },
    payload: {
      kind: "text",
      transcript: "Le ferry pour Paros, quarante-cinq minutes de traversée.",
      capturedAt: "2026-07-12T18:00:00.000Z",
    },
  });
  expect(entry.statusCode).toBe(201);
  return memoId;
}

describe("l'accalmie avant de composer", () => {
  it("laisse le temps d'ajouter un souvenir, puis compte l'accalmie depuis lui", async () => {
    const memoId = await carnetAvecUnSouvenir();

    const attente = waitUntilSettled(harness.prisma, memoId, true);

    // Le voyageur ajoute quelque chose pendant qu'on attend : une photo
    // choisie, un second vocal. On mesure depuis l'instant où c'est **écrit**
    // en base, le seul que l'attente puisse voir.
    await new Promise((resolve) => setTimeout(resolve, 100));
    await harness.prisma.entry.updateMany({
      where: { memoId },
      data: { redactedText: "Le ferry pour Paros, et la plage juste après." },
    });
    const touche = Date.now();

    expect(await attente).toBe(0);
    // L'accalmie entière après le dernier changement, à un pas de scrutation
    // près : la composition n'est pas partie sur le carnet d'avant la photo.
    expect(Date.now() - touche).toBeGreaterThanOrEqual(STRUCTURE_TIMING.settleQuietMs - 40);
    // Et elle n'a pas attendu le plafond pour autant.
    expect(Date.now() - touche).toBeLessThan(STRUCTURE_TIMING.redactionWaitMs);
  });

  it("n'attend pas quand c'est le voyageur qui ouvre l'aperçu", async () => {
    const memoId = await carnetAvecUnSouvenir();

    const commence = Date.now();
    const pending = await waitUntilSettled(harness.prisma, memoId, false);

    expect(pending).toBe(0);
    // Le souvenir vient d'être écrit : une composition de fond aurait attendu
    // ses 300 ms. Celui qui regarde l'écran, non.
    expect(Date.now() - commence).toBeLessThan(200);
  });

  it("n'attend plus rien d'un carnet que personne n'a touché", async () => {
    const memoId = await carnetAvecUnSouvenir();
    // Le carnet a été rempli il y a une heure : l'accalmie est déjà passée.
    const vieux = new Date(Date.now() - 60 * 60 * 1000);
    await harness.prisma.entry.updateMany({ where: { memoId }, data: { updatedAt: vieux } });
    await harness.prisma.memoStep.updateMany({ where: { memoId }, data: { updatedAt: vieux } });
    await harness.prisma.memo.update({ where: { id: memoId }, data: { updatedAt: vieux } });

    const commence = Date.now();
    await waitUntilSettled(harness.prisma, memoId, true);

    // L'accalmie se compte depuis le dernier changement, pas depuis le départ
    // du job : sinon chaque composition de fond paierait 45 s pour rien.
    expect(Date.now() - commence).toBeLessThan(200);
  });

  it("attend toujours une rédaction en cours, et dit ce qui reste au plafond", async () => {
    const memoId = await carnetAvecUnSouvenir();
    await harness.prisma.entry.updateMany({
      where: { memoId },
      data: { redactionStatus: "processing" },
    });

    // Le plafond de trois minutes est inchangé, et ce qu'on rend au bout
    // alimente la branche d'échec du job : un texte pas encore écrit ne
    // s'imprime pas en transcription brute.
    const pending = await waitUntilSettled(harness.prisma, memoId, false);
    expect(pending).toBe(1);
  });
});

describe("ce que MEMO promet quand les photos sont validées", () => {
  it("dit que la page se prépare, sans envoyer la regarder tout de suite", () => {
    // La composition prend une à deux minutes, et depuis T307 elle attend
    // d'abord une accalmie : promettre un aperçu dans la seconde envoyait le
    // voyageur sur la version d'avant.
    expect(PHOTOS_VALIDATED).toContain("se prépare");
    expect(PHOTOS_VALIDATED).not.toContain("prévisualiser");
    expect(PHOTOS_VALIDATED_BEFORE_RETURN).not.toContain("prévisualiser");
  });

  it("laisse le temps d'ajouter un vocal ou des photos", () => {
    // « Mieux vaut laisser le temps d'ajouter un vocal ou des photos »
    // (Hugo, 08/11/2026) : la phrase le dit, et ne referme pas l'étape.
    expect(PHOTOS_VALIDATED).toContain("c’est encore le moment");
    expect(PHOTOS_VALIDATED).not.toContain("étape suivante");
  });

  it("offre d'abord de raconter, l'aperçu restant à un appui", () => {
    const apres = SCRIPTED_ANSWERS["photos-ok"];
    expect(apres?.text).toBe(PHOTOS_VALIDATED);

    const puces = SUGGESTION_SETS[apres!.suggestions];
    expect(puces[0]).toBe("dictate");
    expect(puces).toContain("preview");
    // Et jamais « photos » : les redemander à qui vient de les valider, c'est
    // le détail qui dit qu'il n'y a personne en face.
    expect(puces).not.toContain("photos");
  });
});
