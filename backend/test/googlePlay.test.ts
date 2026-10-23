import { exportPKCS8, generateKeyPair, jwtVerify, SignJWT, type CryptoKey } from "jose";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createGooglePlay, GOOGLE_PLAY_NOTIFICATION, parseSubscriptionPurchase } from "../src/services/googlePlay.js";
import { googlePlayState } from "../src/services/googlePlaySubscriptions.js";
import { renderSubscriptionReminderMail } from "../src/services/mailTemplates.js";
import { armedAppleRenewal } from "../src/services/notifications.js";
import { GOOGLE_PLAY_PRODUCT_IDS, googlePlaySubscriptionsUrl } from "../src/services/subscriptionCatalog.js";
import { hasUnlimitedAccess } from "../src/services/subscriptions.js";
import { createHarness, registerAccount, resetDatabase, testEnv, type TestHarness } from "./helpers.js";

/**
 * L'abonnement Google Play (lot B4) : la route de l'app, le webhook des
 * notifications temps réel, la résiliation, et ce que le reste du serveur en
 * lit. Voir `services/googlePlay.ts`.
 *
 * **Aucun appel à Google** : le vrai client (`createGooglePlay`) tourne, mais
 * contre un `fetch` double qui joue l'OAuth, `subscriptionsv2.get` et
 * `:acknowledge`. Le JWT du compte de service et le jeton OIDC du push sont
 * signés par des clés générées ici — ce sont les vrais contrôles qui les
 * vérifient.
 */

const DAY = 86_400_000;
const MONTHLY = GOOGLE_PLAY_PRODUCT_IDS.monthlySubscription;
const PACKAGE = "com.memobook.app";
const AUDIENCE = "https://api.test/v1/webhooks/google-play";
const PUSHER = "play-rtdn@memobook.iam.gserviceaccount.com";
const TOKEN_URI = "https://oauth2.test/token";

/** Ce que Google dirait de chaque jeton — `SubscriptionPurchaseV2`, en JSON. */
const purchases = new Map<string, Record<string, unknown>>();
const acknowledged: string[] = [];
let oauthCalls = 0;
let googleDown = false;

let serviceKeys: { publicKey: CryptoKey; privateKey: CryptoKey };
let pushKeys: { publicKey: CryptoKey; privateKey: CryptoKey };
let serviceAccountJson: string;
let harness: TestHarness;

const fakeFetch: typeof fetch = async (input, init) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  if (googleDown) return new Response("{}", { status: 503 });

  if (url === TOKEN_URI) {
    oauthCalls += 1;
    // L'assertion doit être signée par la clé du compte de service, pour le bon
    // destinataire et la bonne portée.
    const assertion = new URLSearchParams(typeof init?.body === "string" ? init.body : "").get("assertion") ?? "";
    const { payload } = await jwtVerify(assertion, serviceKeys.publicKey, {
      issuer: "play@memobook.iam.gserviceaccount.com",
      audience: TOKEN_URI,
    });
    expect(payload["scope"]).toBe("https://www.googleapis.com/auth/androidpublisher");
    return Response.json({ access_token: "ya29.test", expires_in: 3600 });
  }

  expect((init?.headers as Record<string, string>)["authorization"]).toBe("Bearer ya29.test");
  const prefix = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/purchases/`;
  if (!url.startsWith(prefix)) return new Response("{}", { status: 404 });
  const path = url.slice(prefix.length);

  const read = path.match(/^subscriptionsv2\/tokens\/(.+)$/);
  if (read) {
    const body = purchases.get(decodeURIComponent(read[1]!));
    return body ? Response.json(body) : new Response("{}", { status: 404 });
  }

  const ack = path.match(/^subscriptions\/(.+)\/tokens\/(.+):acknowledge$/);
  if (ack && init?.method === "POST") {
    const token = decodeURIComponent(ack[2]!);
    acknowledged.push(token);
    const body = purchases.get(token);
    if (body) body["acknowledgementState"] = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";
    return Response.json({});
  }
  return new Response("{}", { status: 404 });
};

function playWith(overrides: Record<string, string> = {}) {
  return createGooglePlay(
    {
      ...testEnv(),
      GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: serviceAccountJson,
      GOOGLE_PLAY_PUSH_AUDIENCE: AUDIENCE,
      GOOGLE_PLAY_PUSH_SERVICE_ACCOUNT: PUSHER,
      ...overrides,
    },
    { fetch: fakeFetch, pushKeys: async () => pushKeys.publicKey },
  );
}

beforeAll(async () => {
  serviceKeys = await generateKeyPair("RS256", { extractable: true });
  pushKeys = await generateKeyPair("RS256");
  serviceAccountJson = JSON.stringify({
    type: "service_account",
    client_email: "play@memobook.iam.gserviceaccount.com",
    private_key_id: "cle-1",
    // Telle que Railway la garde : les retours à la ligne en `\n` littéraux.
    private_key: (await exportPKCS8(serviceKeys.privateKey)).replace(/\n/g, "\\n"),
    token_uri: TOKEN_URI,
  });
  harness = await createHarness({ googlePlay: playWith() });
});

beforeEach(async () => {
  await resetDatabase(harness.prisma);
  harness.context.googlePlay = playWith();
  purchases.clear();
  acknowledged.length = 0;
  oauthCalls = 0;
  googleDown = false;
});

afterAll(async () => {
  await harness?.close();
});

/** Un abonnement mensuel actif chez Google, au nom de ce compte. */
function playPurchase(token: string, accountId: string | null, overrides: Record<string, unknown> = {}) {
  const startTime = new Date(Date.now() - DAY).toISOString();
  const body: Record<string, unknown> = {
    kind: "androidpublisher#subscriptionPurchaseV2",
    startTime,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    latestOrderId: `GPA.${token}`,
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    ...(accountId ? { externalAccountIdentifiers: { obfuscatedExternalAccountId: accountId } } : {}),
    lineItems: [
      {
        productId: MONTHLY,
        expiryTime: new Date(Date.now() + 29 * DAY).toISOString(),
        autoRenewingPlan: {
          autoRenewEnabled: true,
          recurringPrice: { currencyCode: "EUR", units: "4", nanos: 990000000 },
        },
        offerDetails: { basePlanId: "mensuel" },
      },
    ],
    ...overrides,
  };
  purchases.set(token, body);
  return body;
}

async function deliver(authorization: string, purchaseToken: string, extra: Record<string, unknown> = {}) {
  return harness.app.inject({
    method: "POST",
    url: "/v1/subscriptions/google-play",
    headers: { authorization },
    payload: { purchaseToken, productId: MONTHLY, memoId: null, ...extra },
  });
}

async function pushToken(overrides: { audience?: string; email?: string } = {}) {
  return new SignJWT({ email: overrides.email ?? PUSHER, email_verified: true })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer("https://accounts.google.com")
    .setAudience(overrides.audience ?? AUDIENCE)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(pushKeys.privateKey);
}

/** Un push Pub/Sub, comme Google l'envoie. */
async function push(notification: Record<string, unknown>, authorization?: string | null, url = "/v1/webhooks/google-play") {
  const data = Buffer.from(
    JSON.stringify({ version: "1.0", packageName: PACKAGE, eventTimeMillis: String(Date.now()), ...notification }),
  ).toString("base64");
  return harness.app.inject({
    method: "POST",
    url,
    headers: authorization === null ? {} : { authorization: authorization ?? `Bearer ${await pushToken()}` },
    payload: { message: { data, messageId: "1", publishTime: new Date().toISOString() }, subscription: "projects/x/subscriptions/play" },
  });
}

function subscriptionEvent(notificationType: number, purchaseToken: string) {
  return { subscriptionNotification: { version: "1.0", notificationType, purchaseToken, subscriptionId: MONTHLY } };
}

type ProfileBody = {
  subscription: {
    price: number;
    isActive: boolean;
    isUnlimited: boolean;
    managedByAppStore: boolean;
    store: string | null;
    manageUrl: string | null;
    state: string;
  };
};

describe("l'achat depuis l'app Android", () => {
  it("vérifie l'achat chez Google, ouvre l'abonnement, l'acquitte et rend le profil", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);

    const response = await deliver(account.authorization, "jeton-1");

    expect(response.statusCode).toBe(200);
    expect(response.json<ProfileBody>().subscription).toMatchObject({
      price: 4.99,
      isActive: true,
      isUnlimited: true,
      // Le champ que lisent les builds iOS ne ment pas…
      managedByAppStore: false,
      // … et celui d'à côté dit qui tient l'abonnement, et où le gérer.
      store: "google_play",
      manageUrl: googlePlaySubscriptionsUrl(MONTHLY, PACKAGE),
      state: "active",
    });

    const row = await harness.prisma.subscription.findFirstOrThrow({
      where: { accountId: account.accountId },
      include: { transactions: true },
    });
    expect(row).toMatchObject({
      provider: "google_play",
      status: "active",
      providerSubscriptionId: "jeton-1",
      productId: MONTHLY,
      priceCents: 499,
      currency: "EUR",
      autoRenews: true,
      environment: "Production",
    });
    expect(row.transactions).toMatchObject([{ transactionId: "GPA.jeton-1", originalTransactionId: "jeton-1" }]);
    expect(acknowledged).toEqual(["jeton-1"]);
    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(true);
  });

  it("se rejoue sans rien doubler, ni l'abonnement, ni la commande, ni l'acquittement", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);

    expect((await deliver(account.authorization, "jeton-1")).statusCode).toBe(200);
    expect((await deliver(account.authorization, "jeton-1")).statusCode).toBe(200);

    expect(await harness.prisma.subscription.count()).toBe(1);
    expect(await harness.prisma.subscriptionTransaction.count()).toBe(1);
    expect(acknowledged).toEqual(["jeton-1"]);
    // Le jeton OAuth du compte de service sert aux appels suivants.
    expect(oauthCalls).toBe(1);
  });

  it("refuse en 403 un achat fait depuis un autre compte MemoBook", async () => {
    const payer = await registerAccount(harness.app, "payeur@memobook.app");
    const other = await registerAccount(harness.app, "autre@memobook.app");
    playPurchase("jeton-1", payer.accountId);

    const response = await deliver(other.authorization, "jeton-1");

    expect(response.statusCode).toBe(403);
    expect(response.json()).toMatchObject({ error: "transaction_account_mismatch" });
    expect(acknowledged).toEqual([]);
  });

  it("refuse en 409 un abonnement déjà rattaché à un autre compte", async () => {
    const first = await registerAccount(harness.app, "premier@memobook.app");
    const second = await registerAccount(harness.app, "second@memobook.app");
    // Pris dans le Play Store (un code promo) : sans id de compte.
    playPurchase("jeton-1", null);

    expect((await deliver(first.authorization, "jeton-1")).statusCode).toBe(200);
    const response = await deliver(second.authorization, "jeton-1");

    expect(response.statusCode).toBe(409);
    expect(response.json()).toMatchObject({ error: "subscription_owned_elsewhere" });
  });

  it("refuse en 400 un jeton que Google ne connaît pas, un autre produit, un produit inconnu", async () => {
    const account = await registerAccount(harness.app);

    const unknown = await deliver(account.authorization, "jeton-invente");
    expect(unknown.statusCode).toBe(400);
    expect(unknown.json()).toMatchObject({ error: "invalid_purchase" });

    playPurchase("jeton-1", account.accountId, {
      lineItems: [{ productId: "com.memobook.app.autre", expiryTime: new Date(Date.now() + DAY).toISOString() }],
    });
    const mismatch = await deliver(account.authorization, "jeton-1");
    expect(mismatch.statusCode).toBe(400);
    expect(mismatch.json()).toMatchObject({ error: "product_mismatch" });

    const foreign = await deliver(account.authorization, "jeton-1", { productId: "com.memobook.app.autre" });
    expect(foreign.statusCode).toBe(400);
    expect(foreign.json()).toMatchObject({ error: "unknown_product" });

    expect(await harness.prisma.subscription.count()).toBe(0);
  });

  it("laisse un achat en attente de paiement pour plus tard, sans le refuser", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId, { subscriptionState: "SUBSCRIPTION_STATE_PENDING" });

    const response = await deliver(account.authorization, "jeton-1");

    // Ni 400, ni 403, ni 409 : l'app ne le classe pas comme refusé.
    expect(response.statusCode).toBe(422);
    expect(await harness.prisma.subscription.count()).toBe(0);
    expect(acknowledged).toEqual([]);
  });

  it("répond une erreur claire, et non un 500, sans compte de service", async () => {
    harness.context.googlePlay = createGooglePlay(testEnv(), { fetch: fakeFetch });
    const account = await registerAccount(harness.app);

    const response = await deliver(account.authorization, "jeton-1");

    expect(response.statusCode).toBe(503);
    expect(response.json()).toMatchObject({ error: "google_play_unavailable" });
  });

  it("garde l'abonnement ouvert quand l'acquittement échoue : l'app le renverra", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);
    const play = playWith();
    harness.context.googlePlay = {
      ...play,
      async acknowledge() {
        throw new Error("Google en panne");
      },
    };

    const response = await deliver(account.authorization, "jeton-1");

    expect(response.statusCode).toBe(200);
    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(true);
  });
});

describe("la résiliation d'un abonnement Google Play", () => {
  it("n'enregistre que la raison : c'est Google qui résilie, et sa notification qui ferme la ligne", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);
    await deliver(account.authorization, "jeton-1");

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/subscription/cancel",
      headers: { authorization: account.authorization },
      payload: { reason: "tooExpensive" },
    });

    expect(response.statusCode).toBe(200);
    // L'app lit où aller pour le couper.
    expect(response.json<ProfileBody>().subscription).toMatchObject({
      isActive: true,
      store: "google_play",
      manageUrl: googlePlaySubscriptionsUrl(MONTHLY, PACKAGE),
    });
    const row = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(row).toMatchObject({ status: "active", cancelledAt: null, cancellationReason: "tooExpensive" });

    // La personne coupe dans le Play Store ; Google le dit.
    playPurchase("jeton-1", account.accountId, {
      subscriptionState: "SUBSCRIPTION_STATE_CANCELED",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      canceledStateContext: { userInitiatedCancellation: {} },
      lineItems: [
        {
          productId: MONTHLY,
          expiryTime: new Date(Date.now() + 29 * DAY).toISOString(),
          autoRenewingPlan: { autoRenewEnabled: false },
        },
      ],
    });
    expect((await push(subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.canceled, "jeton-1"))).statusCode).toBe(200);

    const closed = await harness.prisma.subscription.findFirstOrThrow({ where: { accountId: account.accountId } });
    expect(closed).toMatchObject({ status: "cancelled", autoRenews: false });
    expect(closed.cancelledAt).not.toBeNull();
    // Le mois payé court encore.
    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(true);
  });
});

describe("les notifications temps réel", () => {
  it("refuse un push sans jeton OIDC, pour une autre audience, ou d'un autre compte de service", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);
    const event = subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.purchased, "jeton-1");

    expect((await push(event, null)).statusCode).toBe(401);
    expect((await push(event, `Bearer ${await pushToken({ audience: "https://ailleurs" })}`)).statusCode).toBe(401);
    expect((await push(event, `Bearer ${await pushToken({ email: "intrus@example.com" })}`)).statusCode).toBe(401);
    expect(await harness.prisma.subscription.count()).toBe(0);
  });

  it("répond 503 tant que le webhook n'est pas configuré, pour que Pub/Sub renvoie", async () => {
    harness.context.googlePlay = playWith({ GOOGLE_PLAY_PUSH_AUDIENCE: "", GOOGLE_PLAY_PUSH_SERVICE_ACCOUNT: "" });
    const response = await push({ testNotification: { version: "1.0" } });
    expect(response.statusCode).toBe(503);
    expect(response.json()).toMatchObject({ error: "webhook_not_configured" });
  });

  it("accepte à défaut le secret partagé de l'URL", async () => {
    harness.context.googlePlay = playWith({ GOOGLE_PLAY_PUSH_AUDIENCE: "", GOOGLE_PLAY_WEBHOOK_SECRET: "s3cret" });
    const test = { testNotification: { version: "1.0" } };
    expect((await push(test, null, "/v1/webhooks/google-play?secret=faux")).statusCode).toBe(401);
    expect((await push(test, null, "/v1/webhooks/google-play?secret=s3cret")).statusCode).toBe(200);
  });

  it("ouvre et acquitte un achat dont l'app n'a pas parlé, au compte de l'achat", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);

    expect((await push(subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.purchased, "jeton-1"))).statusCode).toBe(200);

    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(true);
    expect(acknowledged).toEqual(["jeton-1"]);
  });

  it("n'acquitte pas un achat qu'aucun compte ne porte : Google le remboursera", async () => {
    playPurchase("jeton-1", null);
    expect((await push(subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.purchased, "jeton-1"))).statusCode).toBe(200);
    expect(await harness.prisma.subscription.count()).toBe(0);
    expect(acknowledged).toEqual([]);
  });

  it("suit le renouvellement, le délai de grâce, la suspension et l'expiration", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);
    await deliver(account.authorization, "jeton-1");

    // Renouvelé : une seconde commande, la période avance.
    const nextExpiry = new Date(Date.now() + 59 * DAY);
    playPurchase("jeton-1", account.accountId, {
      latestOrderId: "GPA.jeton-1..0",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      lineItems: [{ productId: MONTHLY, expiryTime: nextExpiry.toISOString(), autoRenewingPlan: { autoRenewEnabled: true } }],
    });
    await push(subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.renewed, "jeton-1"));
    let row = await harness.prisma.subscription.findFirstOrThrow({ include: { transactions: true } });
    expect(row.renewsAt?.toISOString()).toBe(nextExpiry.toISOString());
    expect(row.transactions.map((entry) => entry.transactionId).sort()).toEqual(["GPA.jeton-1", "GPA.jeton-1..0"]);

    // Délai de grâce : Google garde l'accès ouvert.
    purchases.get("jeton-1")!["subscriptionState"] = "SUBSCRIPTION_STATE_IN_GRACE_PERIOD";
    await push(subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.inGracePeriod, "jeton-1"));
    row = await harness.prisma.subscription.findFirstOrThrow({ include: { transactions: true } });
    expect(row.status).toBe("past_due");
    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(true);

    // Suspendu : plus d'accès, même si la fin de période est devant.
    purchases.get("jeton-1")!["subscriptionState"] = "SUBSCRIPTION_STATE_ON_HOLD";
    await push(subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.onHold, "jeton-1"));
    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(false);

    // Expiré.
    purchases.get("jeton-1")!["subscriptionState"] = "SUBSCRIPTION_STATE_EXPIRED";
    await push(subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.expired, "jeton-1"));
    row = await harness.prisma.subscription.findFirstOrThrow({ include: { transactions: true } });
    expect(row).toMatchObject({ status: "expired", autoRenews: false });
    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(false);
  });

  it("ferme l'accès dès la révocation, et marque la commande remboursée", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);
    await deliver(account.authorization, "jeton-1");

    purchases.get("jeton-1")!["subscriptionState"] = "SUBSCRIPTION_STATE_EXPIRED";
    await push({ voidedPurchaseNotification: { purchaseToken: "jeton-1", orderId: "GPA.jeton-1", productType: 1, refundType: 1 } });

    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(false);
    const order = await harness.prisma.subscriptionTransaction.findFirstOrThrow();
    expect(order.revokedAt).not.toBeNull();
  });

  it("ferme l'ancien jeton quand un réabonnement le remplace", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);
    await deliver(account.authorization, "jeton-1");

    playPurchase("jeton-2", account.accountId, { linkedPurchaseToken: "jeton-1" });
    await deliver(account.authorization, "jeton-2");

    const rows = await harness.prisma.subscription.findMany({ orderBy: { createdAt: "asc" } });
    expect(rows.map((row) => [row.providerSubscriptionId, row.status])).toEqual([
      ["jeton-1", "expired"],
      ["jeton-2", "active"],
    ]);
    expect(await hasUnlimitedAccess(harness.prisma, account.accountId)).toBe(true);
  });

  it("acquitte une notification de test, ignore un autre paquet, et demande un renvoi quand Google ne répond pas", async () => {
    expect((await push({ testNotification: { version: "1.0" } })).statusCode).toBe(200);

    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);
    expect(
      (await push({ ...subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.purchased, "jeton-1"), packageName: "com.autre.app" }))
        .statusCode,
    ).toBe(200);
    expect(await harness.prisma.subscription.count()).toBe(0);

    googleDown = true;
    expect((await push(subscriptionEvent(GOOGLE_PLAY_NOTIFICATION.purchased, "jeton-1"))).statusCode).toBe(503);
  });
});

describe("ce que le reste du serveur en lit", () => {
  it("le rappel de résiliation et l'e-mail de fin de voyage parlent du Play Store à un abonné Android", async () => {
    const now = new Date();
    const renewal = armedAppleRenewal(
      [{ provider: "google_play", status: "active", autoRenews: true, renewsAt: new Date(now.getTime() + 5 * DAY) }],
      now,
    );
    expect(renewal?.store).toBe("google_play");

    const mail = renderSubscriptionReminderMail(
      {
        to: "voyageur@memobook.app",
        firstName: "Hugo",
        trip: { title: "Rome 2026", city: "Rome" },
        unlimitedUntil: new Date("2026-11-01T09:00:00Z"),
        bookEstimateCents: null,
        store: "google_play",
      },
      googlePlaySubscriptionsUrl(),
    );
    expect(mail.text).toContain("Play Store ▸ ton profil ▸ Paiements et abonnements ▸ Abonnements");
    expect(mail.text).not.toContain("iPhone");
    expect(mail.html).not.toContain("iPhone");
  });

  it("l'accueil propose de couper un abonnement Google Play qui survit au voyage", async () => {
    const account = await registerAccount(harness.app);
    playPurchase("jeton-1", account.accountId);
    await deliver(account.authorization, "jeton-1");

    const home = await harness.app.inject({ method: "GET", url: "/v1/home", headers: { authorization: account.authorization } });
    expect(home.json<{ traveller: Record<string, unknown> }>().traveller).toMatchObject({
      subscriptionOutlivesTrip: true,
      subscriptionStore: "google_play",
    });
  });

  it("ne rouvre pas l'illimité à un abonnement en pause dont la période est devant", () => {
    const now = new Date();
    const paused = parseSubscriptionPurchase("jeton", {
      subscriptionState: "SUBSCRIPTION_STATE_PAUSED",
      lineItems: [{ productId: MONTHLY, expiryTime: new Date(now.getTime() + 10 * DAY).toISOString() }],
    });
    expect(googlePlayState(paused, now, false)).toMatchObject({ status: "expired", renewsAt: now });
  });
});
