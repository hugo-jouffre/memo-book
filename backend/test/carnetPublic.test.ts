import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **Lire un carnet de la galerie** — `GET /v1/gallery/:id` (T236).
 *
 * Deux choses à tenir, et la seconde compte plus que la première : que le récit
 * arrive **en entier**, et qu'il n'arrive avec **rien d'identifiant**. Ce que
 * montre un carnet public a été arrêté par Hugo le 23/11/2026 ; les tests de la
 * seconde moitié de ce fichier sont là pour qu'un champ ajouté par distraction
 * dans `publicBookSelect` fasse rougir quelque chose.
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

interface PublicBookBody {
  book: {
    id: string;
    title: string;
    dates: string | null;
    summary: string | null;
    coverPhotoUrl: string | null;
    destinations: { name: string; countryCode: string | null }[];
    pageCount: number;
    memoryCount: number;
    steps: {
      id: string;
      number: number;
      place: string | null;
      countryCode: string | null;
      dates: string | null;
      photoUrl: string | null;
      transport: string | null;
      story: string[];
      photoUrls: string[];
    }[];
  };
}

let accessCodeCounter = 0;

/**
 * Un carnet partagé sur la galerie, avec deux étapes, un récit, une photo
 * publiée et une qui ne l'est pas.
 */
async function publicBook(overrides: Record<string, unknown> = {}) {
  const owner = await registerAccount(harness.app, `voyageur${(accessCodeCounter += 1)}@memobook.app`);

  const memo = await harness.prisma.memo.create({
    data: {
      ownerAccountId: owner.accountId,
      title: "Les Cyclades à la voile",
      bookTitle: "D'île en île",
      accessCode: `PUB${String(accessCodeCounter).padStart(3, "0")}`,
      stage: "past",
      isPublicGallery: true,
      coverPhotoUrl: "https://cdn.test/cyclades.jpg",
      destinationName: "Grèce",
      destinationCountryCode: "GR",
      startDate: new Date("2026-06-01T00:00:00Z"),
      endDate: new Date("2026-06-21T00:00:00Z"),
      dayCount: 21,
      pageCount: 92,
      memoryCount: 3,
      shareSlug: "jeton-secret-du-partage",
      ...overrides,
    },
  });

  const paros = await harness.prisma.memoStep.create({
    data: {
      memoId: memo.id,
      number: 1,
      placeName: "Paros",
      destinationName: "Grèce",
      destinationCountryCode: "GR",
      startDate: new Date("2026-06-01T00:00:00Z"),
      endDate: new Date("2026-06-08T00:00:00Z"),
      // **Ce que l'étape raconte**, et c'est ça que la page publique affiche
      // depuis T308 — les deux dates au-dessus sont celles des
      // enregistrements, que personne n'a données.
      livedFromDay: new Date("2026-06-01T00:00:00Z"),
      livedToDay: new Date("2026-06-08T00:00:00Z"),
      photoUrl: "https://cdn.test/paros.jpg",
      transport: "boat",
    },
  });

  const naxos = await harness.prisma.memoStep.create({
    data: { memoId: memo.id, number: 2, placeName: "Naxos", transport: "boat" },
  });

  await harness.prisma.entry.create({
    data: {
      memoId: memo.id,
      stepId: paros.id,
      kind: "audio",
      capturedAt: new Date("2026-06-02T09:00:00Z"),
      transcript: "euh alors on est arrivés au port",
      redactedText: "Nous sommes arrivés au port de Paros au petit matin.",
    },
  });

  await harness.prisma.entry.create({
    data: {
      memoId: memo.id,
      stepId: paros.id,
      kind: "audio",
      capturedAt: new Date("2026-06-03T09:00:00Z"),
      redactedText: "La version de la machine.",
      // Un texte corrigé à la main fait foi — c'est lui que le carnet imprime.
      editedText: "Le deuxième jour, le vent est tombé.",
    },
  });

  await harness.prisma.entry.create({
    data: {
      memoId: memo.id,
      stepId: naxos.id,
      kind: "audio",
      capturedAt: new Date("2026-06-10T09:00:00Z"),
      redactedText: "Naxos sentait le thym.",
    },
  });

  return { memo, paros, naxos, owner };
}

async function read(id: string) {
  // **Aucune autorisation** : c'est tout l'objet de la route.
  return harness.app.inject({ method: "GET", url: `/v1/gallery/${id}` });
}

describe("lire un carnet de la galerie", () => {
  it("s'ouvre sans compte", async () => {
    const { memo } = await publicBook();

    const response = await read(memo.id);

    expect(response.statusCode).toBe(200);
    // Une vitrine se regarde sans être entré : c'est à ça qu'elle sert.
    expect(response.json<PublicBookBody>().book.id).toBe(memo.id);
  });

  it("rend le titre du carnet, ses dates et ses chiffres", async () => {
    const { memo } = await publicBook();

    const book = (await read(memo.id)).json<PublicBookBody>().book;

    // Le titre que le récit s'est donné passe devant celui du voyage : c'est
    // celui qui est imprimé en couverture.
    expect(book.title).toBe("D'île en île");
    expect(book.dates).toBe("du 1er au 21 juin 2026");
    expect(book.coverPhotoUrl).toBe("https://cdn.test/cyclades.jpg");
    expect(book.pageCount).toBe(92);
    expect(book.memoryCount).toBe(3);
    // La même phrase que sur la carte : déduite ici, faute de `gallerySummary`.
    expect(book.summary).toBe("3 semaines");
  });

  it("rend le récit entier, étape par étape, dans l'ordre vécu", async () => {
    const { memo } = await publicBook();

    const steps = (await read(memo.id)).json<PublicBookBody>().book.steps;

    expect(steps.map((step) => step.place)).toEqual(["Paros", "Naxos"]);
    expect(steps[0]?.dates).toBe("du 1er au 8 juin 2026");
    // Naxos n'a pas dit ce qu'elle racontait : elle n'affiche aucune date,
    // plutôt que celle de ses enregistrements (T308).
    expect(steps[1]?.dates).toBeNull();
    expect(steps[0]?.photoUrl).toBe("https://cdn.test/paros.jpg");
    expect(steps[0]?.transport).toBe("boat");
    // Les deux souvenirs de Paros, dans l'ordre, et le texte **du carnet** : la
    // version corrigée à la main pour le second, jamais la transcription brute.
    expect(steps[0]?.story).toEqual([
      "Nous sommes arrivés au port de Paros au petit matin.",
      "Le deuxième jour, le vent est tombé.",
    ]);
    expect(steps[1]?.story).toEqual(["Naxos sentait le thym."]);
  });

  it("garde la transcription quand le voyageur l'a choisie", async () => {
    const { memo, naxos } = await publicBook();
    await harness.prisma.entry.create({
      data: {
        memoId: memo.id,
        stepId: naxos.id,
        kind: "audio",
        capturedAt: new Date("2026-06-11T09:00:00Z"),
        transcript: "et là, le patron du port nous fait signe",
        redactedText: "Le capitaine du port nous fit signe.",
        // « Garder ma transcription » : ce choix fait le carnet, et un carnet
        // public **est** le carnet — contrairement à la vignette d'un lien
        // partagé, qui rend toujours le texte relu (`sharePage.ts`).
        prefersTranscript: true,
      },
    });

    const steps = (await read(memo.id)).json<PublicBookBody>().book.steps;

    expect(steps[1]?.story).toEqual([
      "Naxos sentait le thym.",
      "et là, le patron du port nous fait signe",
    ]);
  });

  it("ne sert que les photos publiées au CDN", async () => {
    const { memo, paros } = await publicBook();

    const publiee = await harness.prisma.mediaAsset.create({
      data: {
        storageKey: "trip-photos/une.jpg",
        mimeType: "image/jpeg",
        bytes: 1_024,
        cdnUrl: "https://cdn.test/une.jpg",
      },
    });
    const dansLeSeau = await harness.prisma.mediaAsset.create({
      data: {
        storageKey: "trip-photos/deux.jpg",
        mimeType: "image/jpeg",
        bytes: 1_024,
        // Jamais publiée : elle ne vit que dans notre seau.
        cdnUrl: null,
      },
    });

    await harness.prisma.entry.createMany({
      data: [
        { memoId: memo.id, stepId: paros.id, kind: "photo", mediaId: publiee.id },
        { memoId: memo.id, stepId: paros.id, kind: "photo", mediaId: dansLeSeau.id },
      ],
    });

    const steps = (await read(memo.id)).json<PublicBookBody>().book.steps;

    // Une seule des deux : notre seau est privé, et la galerie se regarde sans
    // compte (T43).
    expect(steps[0]?.photoUrls).toEqual(["https://cdn.test/une.jpg"]);
    // Et une photo n'est pas un paragraphe du récit.
    expect(steps[0]?.story).toHaveLength(2);
  });

  it("répond 404 pour un carnet qui n'est pas dans la galerie", async () => {
    const { memo } = await publicBook({ isPublicGallery: false });

    // Et **404**, pas 403 : un 403 confirmerait qu'un carnet existe là, ce qui
    // est déjà une information sur quelqu'un.
    expect((await read(memo.id)).statusCode).toBe(404);
  });

  it("répond 404 pour un carnet jeté", async () => {
    const { memo } = await publicBook({ deletedAt: new Date() });

    expect((await read(memo.id)).statusCode).toBe(404);
  });

  it("répond 404 pour un identifiant inconnu, et 400 pour un qui n'en est pas un", async () => {
    expect((await read("3f1d4e8a-0000-4000-8000-000000000000")).statusCode).toBe(404);
    expect((await read("pas-un-uuid")).statusCode).toBe(400);
  });
});

describe("ce qu'un carnet public ne montre pas", () => {
  /** La réponse entière, à plat, pour y chercher ce qui ne doit pas y être. */
  async function rawBody(id: string) {
    return (await read(id)).body;
  }

  it("ne dit pas qui a écrit le carnet", async () => {
    const { memo, owner } = await publicBook();

    const body = await rawBody(memo.id);

    // Ni le compte, ni son adresse : un carnet public ne dit pas **qui** l'a
    // écrit.
    expect(body).not.toContain(owner.accountId);
    expect(body).not.toContain("@memobook.app");
    expect(body).not.toContain("ownerAccountId");
  });

  it("ne nomme pas les co-voyageurs", async () => {
    const { memo } = await publicBook();
    const compagnon = await registerAccount(harness.app, "fanny@memobook.app");
    await harness.prisma.memoMember.create({
      data: { memoId: memo.id, accountId: compagnon.accountId, status: "active" },
    });

    const body = await rawBody(memo.id);

    // Partager son carnet n'est pas partager le nom des gens avec qui on a
    // voyagé : eux n'ont rien coché.
    expect(body).not.toContain(compagnon.accountId);
    expect(body).not.toContain("fanny");
    expect(body).not.toContain("companions");
  });

  it("ne rend pas la conversation avec MEMO", async () => {
    const { memo } = await publicBook();
    await harness.prisma.chatMessage.create({
      data: {
        memoId: memo.id,
        author: "memo",
        kind: "text",
        text: "Raconte-moi ce coucher de soleil, Hugo.",
      },
    });

    const body = await rawBody(memo.id);

    // L'atelier n'est pas le carnet : on y hésite, on y répond à des questions,
    // et rien n'y est destiné à être lu par quelqu'un d'autre.
    expect(body).not.toContain("Raconte-moi");
    expect(body).not.toContain("messages");
  });

  it("ne distribue ni le code d'accès ni le jeton de partage", async () => {
    const { memo } = await publicBook();

    const body = await rawBody(memo.id);

    // Le premier fait **entrer** dans le voyage ; le second ouvre une page
    // publique qu'il n'appartient pas à cette route de distribuer.
    expect(body).not.toContain(memo.accessCode);
    expect(body).not.toContain("jeton-secret-du-partage");
  });

  it("ne rend pas la transcription brute d'un souvenir relu", async () => {
    const { memo } = await publicBook();

    const body = await rawBody(memo.id);

    // Le premier souvenir a une transcription *et* un texte rédigé : c'est le
    // second que le carnet imprime, et le premier ne doit pas voyager avec.
    expect(body).not.toContain("euh alors");
    expect(body).not.toContain("transcript");
  });
});
