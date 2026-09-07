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
  claimedMemos: number;
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

/** Un voyage complet, tel que l'accueil doit le montrer. */
async function seedTrip(accountId: string, deviceId: string, overrides = {}) {
  return harness.prisma.memo.create({
    data: {
      deviceId,
      ownerAccountId: accountId,
      title: "Rome 2026",
      stage: "ongoing",
      destinationName: "Italie",
      destinationCountryCode: "IT",
      memoryCount: 4,
      pageCount: 9,
      members: {
        create: [{ accountId, role: "owner", status: "active", acceptedAt: new Date() }],
      },
      ...overrides,
    },
  });
}

describe("l'accueil", () => {
  it("rend le voyageur, ses voyages et rien d'autre", async () => {
    const account = await registerAccount(harness.app);
    const device = await registerDevice(harness.app);
    await seedTrip(account.accountId, device.deviceId);

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
    const device = await registerDevice(harness.app);
    await seedTrip(account.accountId, device.deviceId, { stage: "upcoming" });

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
    const device = await registerDevice(harness.app);
    const memo = await seedTrip(owner.accountId, device.deviceId);

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
    const device = await registerDevice(harness.app);
    const memo = await seedTrip(owner.accountId, device.deviceId);

    await harness.prisma.memoMember.create({
      data: {
        memoId: memo.id,
        accountId: guest.accountId,
        role: "guest",
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
    const device = await registerDevice(harness.app);
    const memo = await seedTrip(owner.accountId, device.deviceId);

    await harness.prisma.memoMember.create({
      data: { memoId: memo.id, accountId: guest.accountId, role: "guest", status: "removed" },
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
    const device = await registerDevice(harness.app);
    const memo = await seedTrip(account.accountId, device.deviceId, {
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
  it("transfère au compte les carnets racontés avant l'inscription", async () => {
    const device = await registerDevice(harness.app);

    const created = await harness.app.inject({
      method: "POST",
      url: "/v1/memos",
      headers: { authorization: device.authorization },
      payload: { title: "Week-end improvisé" },
    });
    expect(created.statusCode).toBe(201);

    const account = await registerAccount(harness.app);

    const before = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: account.authorization },
    });
    expect(before.json<HomeBody>().trips).toEqual([]);

    const link = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/link-device",
      headers: { authorization: account.authorization },
      payload: { deviceToken: device.authorization.replace("Bearer ", "") },
    });
    expect(link.json<LinkBody>().claimedMemos).toBe(1);

    const after = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: account.authorization },
    });
    expect(after.json<HomeBody>().trips).toHaveLength(1);
  });

  it("est rejouable sans rien dupliquer", async () => {
    const device = await registerDevice(harness.app);
    await harness.app.inject({
      method: "POST",
      url: "/v1/memos",
      headers: { authorization: device.authorization },
      payload: { title: "Week-end improvisé" },
    });

    const account = await registerAccount(harness.app);
    const token = device.authorization.replace("Bearer ", "");

    await harness.app.inject({
      method: "POST",
      url: "/v1/profile/link-device",
      headers: { authorization: account.authorization },
      payload: { deviceToken: token },
    });

    const second = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/link-device",
      headers: { authorization: account.authorization },
      payload: { deviceToken: token },
    });

    expect(second.json<LinkBody>().claimedMemos).toBe(0);
    expect(
      await harness.prisma.memoMember.count({ where: { accountId: account.accountId } }),
    ).toBe(1);
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

    // Sans ce refus, emprunter le téléphone de quelqu'un suffirait à
    // s'approprier ses carnets.
    const second = await registerAccount(harness.app, "second@memobook.app");
    const stolen = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/link-device",
      headers: { authorization: second.authorization },
      payload: { deviceToken: token },
    });

    expect(stolen.statusCode).toBe(409);
  });

  it("ne prend pas les carnets déjà possédés par un autre compte", async () => {
    const device = await registerDevice(harness.app);
    const previous = await registerAccount(harness.app, "ancien@memobook.app");
    await seedTrip(previous.accountId, device.deviceId);

    // L'appareil est libre — il n'a jamais été rattaché — mais son carnet a
    // déjà un propriétaire.
    const newcomer = await registerAccount(harness.app, "nouveau@memobook.app");
    const link = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/link-device",
      headers: { authorization: newcomer.authorization },
      payload: { deviceToken: device.authorization.replace("Bearer ", "") },
    });

    expect(link.json<LinkBody>().claimedMemos).toBe(0);

    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: newcomer.authorization },
    });
    expect(home.json<HomeBody>().trips).toEqual([]);
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
