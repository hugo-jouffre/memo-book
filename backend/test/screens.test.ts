import { afterAll, beforeEach, describe, expect, it } from "vitest";
import {
  createHarness,
  registerAccount,
  registerDevice,
  resetDatabase,
  type TestHarness,
} from "./helpers.js";

/**
 * Les trois écrans « produit » : l'accueil, un voyage, le profil.
 *
 * Ce qui est vérifié ici n'est pas la mise en forme mais **ce dont l'app iOS
 * dépend pour décoder**. Un champ non optionnel de `MemoBookCore` qui manque
 * fait échouer tout l'écran, pas seulement sa ligne : ces tests sont ce qui
 * empêche de le découvrir dans Xcode.
 *
 * Et la règle qui compte plus que les autres : **on ne voit que ses voyages, et
 * ceux où l'on est invité.**
 */

/**
 * Les formes lues par les tests, réduites à ce qu'ils vérifient. Elles ne
 * redécrivent pas les modèles Swift : ce sont les mêmes clés, et c'est
 * précisément ce que ces tests protègent.
 */
interface TripBody {
  id: string;
  title: string;
  stage: string;
  isPrintable: boolean;
  destination: { name: string; countryCode: string | null } | null;
  stats: Record<string, number | null>;
  companions: { id: string; name: string }[];
  progress: { memoryCount: number; pageCount: number; targetPageCount: number } | null;
}

interface HomeBody {
  traveller: { id: string; firstName: string };
  trips: TripBody[];
}

interface StepBody {
  placeName: string | null;
  transport: string | null;
  companions: { id: string }[];
}

interface TripDetailBody {
  trip: TripBody;
  prompt: string | null;
  steps: StepBody[];
}

interface ProfileBody {
  phoneNumber: string | null;
  wantsNewsletter: boolean;
  walletBalance: number;
  address: { street: string; postalCode: string; city: string; country: string };
  connectors: { id: string; isEnabled: boolean }[];
  subscription: { weeklyPrice: number; isActive: boolean };
  orders: unknown[];
}

interface LinkBody {
  deviceId: string;
}

interface WelcomeBody {
  showcases: { title: string }[];
}

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

/**
 * Un voyage complet, tel que l'accueil doit le montrer.
 *
 * Un compte suffit à en créer un : la propriété tient dans `ownerAccountId`,
 * sans appareil ni ligne de participant pour le propriétaire.
 */
async function seedTrip(accountId: string, overrides = {}) {
  return harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Rome 2026",
      stage: "ongoing",
      destinationName: "Italie",
      destinationCountryCode: "IT",
      memoryCount: 4,
      pageCount: 9,
      ...overrides,
    },
  });
}

describe("l'accueil", () => {
  it("rend le voyageur, ses voyages et rien d'autre", async () => {
    const account = await registerAccount(harness.app);
    await seedTrip(account.accountId);

    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: account.authorization },
    });

    expect(response.statusCode).toBe(200);
    const body = response.json<HomeBody>();

    expect(body.traveller.firstName).toBe("Hugo");
    expect(body.trips).toHaveLength(1);

    const trip = body.trips[0];
    if (!trip) throw new Error("l'accueil n'a rendu aucun voyage");

    // Les champs que Swift exige : les omettre casse l'écran entier.
    expect(trip).toMatchObject({
      title: "Rome 2026",
      stage: "ongoing",
      isPrintable: false,
      destination: { name: "Italie", countryCode: "IT" },
    });
    expect(trip.stats).toBeDefined();
    expect(trip.companions).toEqual([]);
    expect(trip.progress).toEqual({ memoryCount: 4, pageCount: 9, targetPageCount: 60 });
  });

  it("ne donne pas de progression à un voyage qui n'a pas commencé", async () => {
    const account = await registerAccount(harness.app);
    await seedTrip(account.accountId, { stage: "upcoming" });

    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: account.authorization },
    });

    // Une barre à zéro dirait le contraire de ce qui est vrai : un voyage à
    // venir n'a rien à remplir encore.
    expect(response.json<HomeBody>().trips[0]?.progress).toBeNull();
  });

  it("ne montre pas les voyages des autres", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const stranger = await registerAccount(harness.app, "inconnu@memobook.app");
    const memo = await seedTrip(owner.accountId);

    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: stranger.authorization },
    });
    expect(home.json<HomeBody>().trips).toEqual([]);

    // 404 et non 403 : un 403 confirmerait que le carnet existe.
    const direct = await harness.app.inject({
      method: "GET",
      url: `/v1/trips/${memo.id}`,
      headers: { authorization: stranger.authorization },
    });
    expect(direct.statusCode).toBe(404);
  });

  it("montre à un invité le voyage où il est invité", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const guest = await registerAccount(harness.app, "invitee@memobook.app");
    const memo = await seedTrip(owner.accountId);

    await harness.prisma.memoMember.create({
      data: {
        memoId: memo.id,
        accountId: guest.accountId,
        status: "active",
        acceptedAt: new Date(),
      },
    });

    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: guest.authorization },
    });

    expect(home.json<HomeBody>().trips).toHaveLength(1);

    // Et le propriétaire voit maintenant une pastille de compagnon : le
    // propriétaire lui-même n'en est jamais une sur sa propre couverture.
    const ownerHome = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: owner.authorization },
    });
    expect(ownerHome.json<HomeBody>().trips[0]?.companions).toHaveLength(1);
  });

  it("retire ses voyages à un invité qu'on a sorti", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const guest = await registerAccount(harness.app, "invitee@memobook.app");
    const memo = await seedTrip(owner.accountId);

    await harness.prisma.memoMember.create({
      data: { memoId: memo.id, accountId: guest.accountId, status: "removed" },
    });

    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: guest.authorization },
    });
    expect(home.json<HomeBody>().trips).toEqual([]);
  });
});

describe("un voyage", () => {
  it("rend ses étapes dans l'ordre, avec un transport que Swift sait décoder", async () => {
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId, {
      prompt: "Comment ça se passe à Trastevere ?",
    });

    await harness.prisma.memoStep.createMany({
      data: [
        { memoId: memo.id, number: 2, placeName: "Le Colisée", transport: "walk" },
        { memoId: memo.id, number: 1, placeName: "Trastevere", transport: "plane" },
      ],
    });

    const response = await harness.app.inject({
      method: "GET",
      url: `/v1/trips/${memo.id}`,
      headers: { authorization: account.authorization },
    });

    const body = response.json<TripDetailBody>();
    expect(body.prompt).toBe("Comment ça se passe à Trastevere ?");
    expect(body.steps.map((step) => step.placeName)).toEqual([
      "Trastevere",
      "Le Colisée",
    ]);

    // `TripTransport` **refuse** une valeur inconnue au décodage, contrairement
    // à `TripStage`. Une valeur hors énumération ferait disparaître l'écran.
    const transports = ["walk", "bike", "car", "bus", "train", "boat", "plane"];
    for (const step of body.steps) {
      expect(transports).toContain(step.transport);
      expect(step.companions).toBeDefined();
    }
  });
});

describe("le profil", () => {
  it("rend tout ce que l'écran affiche, en une réponse", async () => {
    const account = await registerAccount(harness.app);

    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { walletBalanceCents: 6788, addressCity: "Lyon" },
    });

    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
    });

    const body = response.json<ProfileBody>();
    // Les centimes deviennent des euros à la frontière, et nulle part avant.
    expect(body.walletBalance).toBe(67.88);
    expect(body.address).toEqual({
      street: "",
      postalCode: "",
      city: "Lyon",
      country: "",
    });
    // Le catalogue complet, pas seulement ce qui est branché : l'écran doit
    // pouvoir proposer les six.
    expect(body.connectors.length).toBeGreaterThan(0);
    expect(body.connectors.every((connector) => !connector.isEnabled)).toBe(true);
    expect(body.subscription).toEqual({ weeklyPrice: 0, isActive: false });
    expect(body.orders).toEqual([]);
  });

  it("distingue « effacer » de « ne pas toucher »", async () => {
    const account = await registerAccount(harness.app);

    await harness.app.inject({
      method: "PATCH",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
      payload: { phoneNumber: "+33 6 12 34 56 78" },
    });

    // Champ absent : le téléphone ne bouge pas.
    const untouched = await harness.app.inject({
      method: "PATCH",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
      payload: { wantsNewsletter: true },
    });
    expect(untouched.json<ProfileBody>().phoneNumber).toBe("+33 6 12 34 56 78");
    expect(untouched.json<ProfileBody>().wantsNewsletter).toBe(true);

    // `null` explicite : le téléphone est effacé.
    const cleared = await harness.app.inject({
      method: "PATCH",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
      payload: { phoneNumber: null },
    });
    expect(cleared.json<ProfileBody>().phoneNumber).toBeNull();
  });

  it("refuse un connecteur qui n'est pas au catalogue", async () => {
    const account = await registerAccount(harness.app);

    const response = await harness.app.inject({
      method: "PUT",
      url: "/v1/profile/connectors/nimporte-quoi",
      headers: { authorization: account.authorization },
      payload: { isEnabled: true },
    });

    expect(response.statusCode).toBe(400);
  });
});

describe("le rattachement d'un appareil", () => {
  it("rattache l'appareil au compte, sans lui transférer quoi que ce soit", async () => {
    const device = await registerDevice(harness.app);
    const account = await registerAccount(harness.app);

    const link = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/link-device",
      headers: { authorization: account.authorization },
      payload: { deviceToken: device.authorization.replace("Bearer ", "") },
    });

    expect(link.statusCode).toBe(200);
    expect(link.json<LinkBody>().deviceId).toBe(device.deviceId);
    expect(
      (await harness.prisma.device.findUniqueOrThrow({ where: { id: device.deviceId } }))
        .accountId,
    ).toBe(account.accountId);
  });

  it("est rejouable", async () => {
    const device = await registerDevice(harness.app);
    const account = await registerAccount(harness.app);
    const token = device.authorization.replace("Bearer ", "");

    for (const _ of [1, 2]) {
      const link = await harness.app.inject({
        method: "POST",
        url: "/v1/profile/link-device",
        headers: { authorization: account.authorization },
        payload: { deviceToken: token },
      });
      expect(link.statusCode).toBe(200);
    }
  });

  it("refuse de reprendre l'appareil de quelqu'un d'autre", async () => {
    const device = await registerDevice(harness.app);
    const first = await registerAccount(harness.app, "premier@memobook.app");
    const token = device.authorization.replace("Bearer ", "");

    await harness.app.inject({
      method: "POST",
      url: "/v1/profile/link-device",
      headers: { authorization: first.authorization },
      payload: { deviceToken: token },
    });

    // Sans ce refus, emprunter le téléphone de quelqu'un suffirait à se
    // rattacher à son installation.
    const second = await registerAccount(harness.app, "second@memobook.app");
    const stolen = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/link-device",
      headers: { authorization: second.authorization },
      payload: { deviceToken: token },
    });

    expect(stolen.statusCode).toBe(409);
  });

  it("ne donne plus accès aux carnets : un token d'appareil n'ouvre rien", async () => {
    const device = await registerDevice(harness.app);

    // Un carnet a toujours un propriétaire, et un propriétaire est un compte :
    // il n'existe plus de chemin pour en créer un sans session.
    const created = await harness.app.inject({
      method: "POST",
      url: "/v1/memos",
      headers: { authorization: device.authorization },
      payload: { title: "Week-end improvisé" },
    });

    expect(created.statusCode).toBe(401);
  });
});

describe("un co-voyageur", () => {
  /** Le voyage de quelqu'un d'autre, sur lequel on est co-voyageur actif. */
  async function sharedTrip(ownerId: string, coTravellerId: string) {
    const memo = await seedTrip(ownerId);
    await harness.prisma.memoMember.create({
      data: {
        memoId: memo.id,
        accountId: coTravellerId,
        status: "active",
        acceptedAt: new Date(),
      },
    });
    return memo;
  }

  it("raconte, génère et commande comme le propriétaire", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const coTraveller = await registerAccount(harness.app, "covoyageur@memobook.app");
    const memo = await sharedTrip(owner.accountId, coTraveller.accountId);

    // Raconter.
    const told = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/entries`,
      headers: { authorization: coTraveller.authorization },
      payload: { kind: "text", transcript: "On est montés au Colisée à l'aube." },
    });
    expect(told.statusCode).toBe(201);

    // Générer.
    const generated = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/renders`,
      headers: { authorization: coTraveller.authorization },
    });
    expect([200, 202]).toContain(generated.statusCode);

    // Commander — et la commande retient que c'est lui, pas le propriétaire :
    // chacun a sa cagnotte.
    const render = await harness.prisma.render.create({
      data: { memoId: memo.id, status: "ready", pdfUrl: "https://pdf.test/rome.pdf" },
    });
    const ordered = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/orders`,
      headers: { authorization: coTraveller.authorization },
      payload: {
        renderId: render.id,
        shipping: {
          name: "Clara",
          line1: "2 rue des Voyages",
          postalCode: "75011",
          city: "Paris",
          country: "FR",
        },
      },
    });

    expect(ordered.statusCode).toBe(201);
    expect(
      (
        await harness.prisma.printOrder.findFirstOrThrow({ where: { memoId: memo.id } })
      ).orderedByAccountId,
    ).toBe(coTraveller.accountId);
  });

  it("ne peut pas supprimer le voyage : c'est le seul geste du propriétaire", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const coTraveller = await registerAccount(harness.app, "covoyageur@memobook.app");
    const memo = await sharedTrip(owner.accountId, coTraveller.accountId);

    const refused = await harness.app.inject({
      method: "DELETE",
      url: `/v1/memos/${memo.id}`,
      headers: { authorization: coTraveller.authorization },
    });

    expect(refused.statusCode).toBe(404);
    expect(await harness.prisma.memo.findUnique({ where: { id: memo.id } })).not.toBeNull();
  });
});

describe("la suppression d'un compte", () => {
  it("emporte ses carnets, ses souvenirs, ses médias et ses commandes", async () => {
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId);

    const media = await harness.prisma.mediaAsset.create({
      data: { storageKey: "audio/souvenir.m4a", mimeType: "audio/mp4", bytes: 12 },
    });
    await harness.prisma.entry.create({
      data: { memoId: memo.id, kind: "audio", status: "ready", mediaId: media.id },
    });

    const render = await harness.prisma.render.create({
      data: { memoId: memo.id, status: "ready", pdfUrl: "https://pdf.test/carnet.pdf" },
    });
    // La commande est le cas piégeux : sa clé vers le rendu est en RESTRICT, et
    // la cascade seule échouerait.
    await harness.prisma.printOrder.create({
      data: {
        memoId: memo.id,
        renderId: render.id,
        shippingName: "Hugo",
        shippingLine1: "1 rue du Carnet",
        shippingPostalCode: "75011",
        shippingCity: "Paris",
        shippingCountry: "FR",
      },
    });

    const response = await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: account.authorization },
    });

    expect(response.statusCode).toBe(204);

    expect(await harness.prisma.account.count()).toBe(0);
    expect(await harness.prisma.memo.count()).toBe(0);
    expect(await harness.prisma.entry.count()).toBe(0);
    expect(await harness.prisma.render.count()).toBe(0);
    expect(await harness.prisma.printOrder.count()).toBe(0);
    expect(await harness.prisma.session.count()).toBe(0);
    // Rien ne référence `media_assets` : sans passe dédiée, la ligne resterait.
    expect(await harness.prisma.mediaAsset.count()).toBe(0);
  });

  it("passe le voyage partagé au co-voyageur au lieu de l'effacer", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const coTraveller = await registerAccount(harness.app, "covoyageur@memobook.app");

    const shared = await seedTrip(owner.accountId);
    await harness.prisma.memoMember.create({
      data: {
        memoId: shared.id,
        accountId: coTraveller.accountId,
        status: "active",
        acceptedAt: new Date(),
      },
    });
    // Un souvenir raconté par celui qui s'en va : il appartient au récit, pas à
    // son auteur, et il reste.
    await harness.prisma.entry.create({
      data: { memoId: shared.id, kind: "text", status: "ready", transcript: "Le Colisée." },
    });
    const own = await seedTrip(coTraveller.accountId, { title: "Son voyage à elle" });

    await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: owner.authorization },
    });

    const after = await harness.prisma.memo.findUnique({ where: { id: shared.id } });
    expect(after?.ownerAccountId).toBe(coTraveller.accountId);
    // Le nouveau propriétaire n'est plus un co-voyageur : il ne peut pas être
    // le compagnon de lui-même.
    expect(await harness.prisma.memoMember.count({ where: { memoId: shared.id } })).toBe(0);
    expect(await harness.prisma.entry.count({ where: { memoId: shared.id } })).toBe(1);
    expect(await harness.prisma.memo.findUnique({ where: { id: own.id } })).not.toBeNull();

    // Et l'écran le montre toujours, désormais comme le sien.
    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: coTraveller.authorization },
    });
    expect(home.json<HomeBody>().trips).toHaveLength(2);
  });

  it("efface le voyage dont personne d'autre ne fait partie", async () => {
    const owner = await registerAccount(harness.app, "seul@memobook.app");
    const invited = await registerAccount(harness.app, "convie@memobook.app");

    const alone = await seedTrip(owner.accountId, { title: "Voyage en solitaire" });
    // Une invitation encore en attente ne désigne personne qui puisse hériter.
    const pending = await seedTrip(owner.accountId, { title: "Invitation en attente" });
    await harness.prisma.memoMember.create({
      data: { memoId: pending.id, invitedEmail: "quelquun@memobook.app", status: "invited" },
    });
    // Et un co-voyageur qu'on a sorti n'hérite pas non plus.
    const removed = await seedTrip(owner.accountId, { title: "Co-voyageur sorti" });
    await harness.prisma.memoMember.create({
      data: { memoId: removed.id, accountId: invited.accountId, status: "removed" },
    });

    await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: owner.authorization },
    });

    expect(await harness.prisma.memo.count()).toBe(0);
  });

  it("ferme la session : le token ne vaut plus rien", async () => {
    const account = await registerAccount(harness.app);

    await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: account.authorization },
    });

    const after = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: account.authorization },
    });

    expect(after.statusCode).toBe(401);
  });
});
describe("l'écran de bienvenue", () => {
  it("sert les mises en avant sans exiger de compte", async () => {
    await harness.prisma.showcase.createMany({
      data: [
        { title: "Islande", showOnWelcomeScreen: true, position: 1 },
        { title: "Jeanne", showOnWelcomeScreen: true, position: 0 },
        { title: "Invisible", showOnWelcomeScreen: false, position: 2 },
      ],
    });

    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/showcases/welcome",
    });

    expect(response.statusCode).toBe(200);
    const titles = response.json<WelcomeBody>().showcases.map((showcase) => showcase.title);
    // Rangées par `position`, et seules celles dont le drapeau est levé.
    expect(titles).toEqual(["Jeanne", "Islande"]);
  });

  it("ignore une mise en avant dont la fenêtre est passée", async () => {
    await harness.prisma.showcase.create({
      data: {
        title: "Campagne finie",
        showOnWelcomeScreen: true,
        endsAt: new Date(Date.now() - 86_400_000),
      },
    });

    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/showcases/welcome",
    });
    expect(response.json<WelcomeBody>().showcases).toEqual([]);
  });
});
