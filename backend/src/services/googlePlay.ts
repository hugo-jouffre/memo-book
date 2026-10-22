import { timingSafeEqual } from "node:crypto";
import {
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
  SignJWT,
  type CryptoKey,
  type JWTPayload,
  type JWTVerifyGetKey,
} from "jose";
import type { Env } from "../env.js";

/**
 * Google Play — **l'abonnement sur Android** (lot B4, 22/10/2026), le pendant
 * de `appStore.ts`.
 *
 * Chez Apple, l'app envoie une transaction **signée** : on vérifie la
 * signature, et c'est tout. Chez Google, l'app n'envoie qu'un **jeton
 * d'achat** — une chaîne opaque qui ne prouve rien. C'est donc le serveur qui
 * demande à Google ce que ce jeton vaut (*Google Play Developer API*,
 * `purchases.subscriptionsv2.get`), avec un compte de service invité dans la
 * Play Console. Sans cet appel, n'importe qui pourrait poster un jeton
 * inventé.
 *
 * Trois pièges, et le fichier est organisé autour d'eux :
 *
 * 1. **Un achat non acquitté est remboursé au bout de trois jours.** Google
 *    attend qu'on lui dise « reçu » (`:acknowledge`). L'app Android ne le fait
 *    jamais elle-même (`SubscriptionStore.settle`) : c'est le serveur, une
 *    fois l'abonnement ouvert — sinon un achat que le serveur n'aurait pas reçu
 *    serait acquitté, et l'app ne le renverrait plus.
 * 2. **Les notifications ne disent presque rien.** Une notification temps réel
 *    porte un type et un jeton, pas l'état : on relit l'abonnement chez Google
 *    à chaque fois, et c'est cette lecture qui fait foi. L'ordre d'arrivée ne
 *    compte donc plus — on écrit toujours l'état du moment.
 * 3. **Un réabonnement change de jeton.** Le nouveau pointe l'ancien
 *    (`linkedPurchaseToken`) : c'est un nouvel abonnement, et l'ancien est
 *    remplacé.
 *
 * Pas de SDK Google : deux appels HTTP et un JWT signé suffisent, et `jose` est
 * déjà là pour Apple et Google Sign-In.
 */

/** L'état d'un abonnement chez Google, dans nos mots (`SubscriptionState`). */
export type GooglePlayState =
  | "pending"
  | "active"
  | "paused"
  | "grace_period"
  | "on_hold"
  | "canceled"
  | "expired"
  | "pending_purchase_canceled"
  | "unknown";

/** Un abonnement Google Play, tel que Google le décrit à l'instant de la lecture. */
export interface GooglePlayPurchase {
  purchaseToken: string;
  productId: string;
  state: GooglePlayState;
  startedAt: Date | null;
  /** La fin de la période en cours (délai de grâce compris quand il court). */
  expiresAt: Date | null;
  /** Le renouvellement est-il armé ? Nul quand Google ne le dit pas. */
  autoRenews: boolean | null;
  /** `obfuscatedExternalAccountId` : l'id du compte MemoBook que l'app a posé à l'achat. */
  accountId: string | null;
  /** La dernière commande (`GPA.…`, puis `GPA.…..0`, `..1` à chaque renouvellement). */
  orderId: string | null;
  /** Le jeton que celui-ci remplace — réabonnement, changement d'offre. */
  linkedPurchaseToken: string | null;
  acknowledged: boolean;
  /** Le prix du plan, TTC, en centimes. Nul quand Google ne le rend pas. */
  priceCents: number | null;
  currency: string | null;
  /** `Sandbox` pour un testeur de licence (`testPurchase`), `Production` sinon. */
  environment: "Production" | "Sandbox";
}

/** Le contenu d'une notification temps réel (`DeveloperNotification`). */
export interface GooglePlayNotification {
  packageName: string;
  eventTime: Date;
  subscription: { notificationType: number; purchaseToken: string } | null;
  voided: { purchaseToken: string; orderId: string | null; productType: number | null } | null;
  isTest: boolean;
}

/**
 * Les types de `subscriptionNotification.notificationType` qu'on nomme. Les
 * autres se traitent pareil : on relit l'abonnement.
 */
export const GOOGLE_PLAY_NOTIFICATION = {
  recovered: 1,
  renewed: 2,
  canceled: 3,
  purchased: 4,
  onHold: 5,
  inGracePeriod: 6,
  restarted: 7,
  paused: 10,
  revoked: 12,
  expired: 13,
  pendingPurchaseCanceled: 20,
} as const;

/** Le serveur n'a pas ce qu'il faut pour parler à Google : rien n'est tenté. */
export class GooglePlayNotConfiguredError extends Error {
  override name = "GooglePlayNotConfiguredError";
}

/** Google ne connaît pas ce jeton pour ce paquet, ou ne le rend pas lisible. */
export class GooglePlayPurchaseError extends Error {
  override name = "GooglePlayPurchaseError";
}

/** Google n'a pas répondu comme il faut — réseau, 5xx, jeton OAuth refusé. À réessayer. */
export class GooglePlayUnavailableError extends Error {
  override name = "GooglePlayUnavailableError";
}

/** Un appel au webhook qui ne vient pas de notre abonnement Pub/Sub. */
export class GooglePlayPushRejectedError extends Error {
  override name = "GooglePlayPushRejectedError";
}

export interface GooglePlay {
  /** Le paquet dont on lit les achats — `com.memobook.app`. */
  readonly packageName: string;
  /** Lit l'abonnement d'un jeton chez Google (`subscriptionsv2.get`). */
  readSubscription(purchaseToken: string): Promise<GooglePlayPurchase>;
  /** Acquitte l'achat — sans quoi Google le rembourse au bout de trois jours. */
  acknowledge(purchase: { purchaseToken: string; productId: string }): Promise<void>;
  /**
   * Vérifie qu'un appel au webhook vient de Pub/Sub : le jeton OIDC de
   * l'en-tête `Authorization`, ou le secret partagé de l'URL.
   */
  verifyPush(request: { authorization: string | undefined; secret: string | undefined }): Promise<void>;
}

export interface GooglePlayOptions {
  /** Le `fetch` des appels à Google — un double dans les tests. */
  fetch?: typeof fetch;
  /** Les clés qui signent les jetons OIDC de Pub/Sub — une clé locale dans les tests. */
  pushKeys?: JWTVerifyGetKey;
}

const API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";
const SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token";
const OIDC_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];

interface ServiceAccount {
  clientEmail: string;
  privateKey: string;
  privateKeyId: string | null;
  tokenUri: string;
}

export function createGooglePlay(env: Env, options: GooglePlayOptions = {}): GooglePlay {
  const fetcher = options.fetch ?? globalThis.fetch;
  // Les clés publiques de Google, lues à la première notification et gardées
  // en mémoire — comme pour Google Sign-In (`socialIdentity.ts`).
  let pushKeys = options.pushKeys;
  const packageName = env.GOOGLE_PLAY_PACKAGE_NAME.trim();

  let account: ServiceAccount | undefined;
  let signingKey: Promise<CryptoKey> | undefined;
  let accessToken: { value: string; expiresAt: number } | undefined;

  function serviceAccount(): ServiceAccount {
    if (account) return account;
    if (env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON.trim() === "") {
      throw new GooglePlayNotConfiguredError("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON est vide.");
    }
    if (packageName === "") {
      throw new GooglePlayNotConfiguredError("GOOGLE_PLAY_PACKAGE_NAME est vide.");
    }
    account = parseServiceAccount(env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON);
    return account;
  }

  /** Un jeton OAuth du compte de service, gardé jusqu'à une minute de sa fin. */
  async function bearer(): Promise<string> {
    if (accessToken && accessToken.expiresAt - 60_000 > Date.now()) return accessToken.value;

    const credentials = serviceAccount();
    signingKey ??= importPKCS8(credentials.privateKey, "RS256").catch((cause: unknown) => {
      signingKey = undefined;
      throw new GooglePlayNotConfiguredError(
        `La clé privée du compte de service Google Play est illisible (${String(cause)}).`,
      );
    });
    const assertion = await new SignJWT({ scope: SCOPE })
      .setProtectedHeader({ alg: "RS256", typ: "JWT", ...(credentials.privateKeyId ? { kid: credentials.privateKeyId } : {}) })
      .setIssuer(credentials.clientEmail)
      .setAudience(credentials.tokenUri)
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(await signingKey);

    const response = await call(credentials.tokenUri, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }).toString(),
    });
    if (!response.ok) {
      throw new GooglePlayUnavailableError(`Jeton OAuth Google refusé (${response.status}).`);
    }
    const body = (await response.json()) as { access_token?: unknown; expires_in?: unknown };
    if (typeof body.access_token !== "string") {
      throw new GooglePlayUnavailableError("Jeton OAuth Google illisible.");
    }
    const lifetime = typeof body.expires_in === "number" ? body.expires_in : 3600;
    accessToken = { value: body.access_token, expiresAt: Date.now() + lifetime * 1000 };
    return accessToken.value;
  }

  async function call(url: string, init: RequestInit): Promise<Response> {
    try {
      return await fetcher(url, { ...init, signal: AbortSignal.timeout(10_000) });
    } catch (cause) {
      throw new GooglePlayUnavailableError(`Google Play injoignable (${String(cause)}).`);
    }
  }

  async function authorized(url: string, init: RequestInit = {}): Promise<Response> {
    const token = await bearer();
    const response = await call(url, {
      ...init,
      headers: { ...(init.headers as Record<string, string> | undefined), authorization: `Bearer ${token}` },
    });
    // Un jeton OAuth révoqué entre-temps : on l'oublie, la prochaine lecture
    // en demandera un autre.
    if (response.status === 401) accessToken = undefined;
    return response;
  }

  return {
    packageName,

    async readSubscription(purchaseToken) {
      serviceAccount();
      const url = `${API}/${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
      const response = await authorized(url);

      // 400 : jeton mal formé ; 404 / 410 : inconnu pour ce paquet, ou trop
      // ancien. Ce n'est pas passager — l'app ne doit pas le renvoyer.
      if (response.status === 400 || response.status === 404 || response.status === 410) {
        throw new GooglePlayPurchaseError(`Google Play ne connaît pas cet achat (${response.status}).`);
      }
      if (!response.ok) {
        throw new GooglePlayUnavailableError(`Google Play a répondu ${response.status}.`);
      }
      return parseSubscriptionPurchase(purchaseToken, await response.json());
    },

    async acknowledge({ purchaseToken, productId }) {
      serviceAccount();
      // `subscriptionsv2` n'a pas d'acquittement : c'est celui de la v1, par
      // produit.
      const url =
        `${API}/${encodeURIComponent(packageName)}/purchases/subscriptions/` +
        `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
      const response = await authorized(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      });
      if (!response.ok) {
        throw new GooglePlayUnavailableError(`Acquittement Google Play refusé (${response.status}).`);
      }
    },

    async verifyPush({ authorization, secret }) {
      const audience = env.GOOGLE_PLAY_PUSH_AUDIENCE.trim();
      if (audience !== "") {
        const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
        if (!token) throw new GooglePlayPushRejectedError("Jeton OIDC du push absent.");
        pushKeys ??= createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));
        let payload: JWTPayload;
        try {
          payload = (await jwtVerify(token, pushKeys, { issuer: OIDC_ISSUERS, audience })).payload;
        } catch (cause) {
          throw new GooglePlayPushRejectedError(`Jeton OIDC du push refusé (${String(cause)}).`);
        }
        const expected = env.GOOGLE_PLAY_PUSH_SERVICE_ACCOUNT.trim();
        // Sans l'adresse, n'importe quel compte Google qui viserait notre
        // audience passerait : l'audience seule ne dit pas qui pousse.
        if (expected === "") {
          throw new GooglePlayNotConfiguredError("GOOGLE_PLAY_PUSH_SERVICE_ACCOUNT est vide.");
        }
        if (payload["email"] !== expected || payload["email_verified"] !== true) {
          throw new GooglePlayPushRejectedError("Le push n'est pas signé par le compte de service attendu.");
        }
        return;
      }

      const shared = env.GOOGLE_PLAY_WEBHOOK_SECRET;
      if (shared !== "") {
        if (secret === undefined || !sameSecret(secret, shared)) {
          throw new GooglePlayPushRejectedError("Secret du webhook Google Play absent ou faux.");
        }
        return;
      }

      throw new GooglePlayNotConfiguredError(
        "Webhook Google Play non configuré : GOOGLE_PLAY_PUSH_AUDIENCE ou GOOGLE_PLAY_WEBHOOK_SECRET.",
      );
    },
  };
}

function sameSecret(given: string, expected: string): boolean {
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * La clé JSON du compte de service. Lue à la première lecture d'un achat, pas
 * au démarrage : une variable mal collée ne doit pas empêcher l'API de partir,
 * seulement l'achat Android de passer — et le dire.
 */
export function parseServiceAccount(raw: string): ServiceAccount {
  let json: Record<string, unknown>;
  try {
    json = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new GooglePlayNotConfiguredError("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON n'est pas un JSON.");
  }
  const clientEmail = json["client_email"];
  const privateKey = json["private_key"];
  if (typeof clientEmail !== "string" || typeof privateKey !== "string") {
    throw new GooglePlayNotConfiguredError(
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON n'a pas de client_email ou de private_key.",
    );
  }
  return {
    clientEmail,
    // Railway garde mal une valeur sur plusieurs lignes : une clé recopiée
    // avec des `\n` littéraux se relit ici (comme `APNS_PRIVATE_KEY`).
    privateKey: privateKey.includes("\\n") ? privateKey.replace(/\\n/g, "\n") : privateKey,
    privateKeyId: typeof json["private_key_id"] === "string" ? json["private_key_id"] : null,
    tokenUri: typeof json["token_uri"] === "string" ? json["token_uri"] : DEFAULT_TOKEN_URI,
  };
}

const STATES: Record<string, GooglePlayState> = {
  SUBSCRIPTION_STATE_PENDING: "pending",
  SUBSCRIPTION_STATE_ACTIVE: "active",
  SUBSCRIPTION_STATE_PAUSED: "paused",
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace_period",
  SUBSCRIPTION_STATE_ON_HOLD: "on_hold",
  SUBSCRIPTION_STATE_CANCELED: "canceled",
  SUBSCRIPTION_STATE_EXPIRED: "expired",
  SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED: "pending_purchase_canceled",
};

/**
 * Une `SubscriptionPurchaseV2`, dans nos mots. Un abonnement MemoBook n'a
 * qu'un produit : la première ligne (`lineItems[0]`) le porte.
 */
export function parseSubscriptionPurchase(purchaseToken: string, raw: unknown): GooglePlayPurchase {
  const body = (raw ?? {}) as Record<string, unknown>;
  const lineItems = Array.isArray(body["lineItems"]) ? (body["lineItems"] as Record<string, unknown>[]) : [];
  const item = lineItems[0];
  const productId = typeof item?.["productId"] === "string" ? item["productId"] : null;
  if (!item || !productId) {
    throw new GooglePlayPurchaseError("Achat Google Play sans produit.");
  }

  const plan = (item["autoRenewingPlan"] ?? null) as Record<string, unknown> | null;
  const price = (plan?.["recurringPrice"] ?? null) as Record<string, unknown> | null;
  const accounts = (body["externalAccountIdentifiers"] ?? {}) as Record<string, unknown>;

  return {
    purchaseToken,
    productId,
    state: STATES[String(body["subscriptionState"])] ?? "unknown",
    startedAt: dateOf(body["startTime"]),
    expiresAt: dateOf(item["expiryTime"]),
    autoRenews: typeof plan?.["autoRenewEnabled"] === "boolean" ? plan["autoRenewEnabled"] : plan ? false : null,
    accountId: stringOf(accounts["obfuscatedExternalAccountId"]),
    orderId: stringOf(item["latestSuccessfulOrderId"]) ?? stringOf(body["latestOrderId"]),
    linkedPurchaseToken: stringOf(body["linkedPurchaseToken"]),
    acknowledged: body["acknowledgementState"] === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    priceCents: centsOf(price),
    currency: stringOf(price?.["currencyCode"]),
    environment: body["testPurchase"] ? "Sandbox" : "Production",
  };
}

/**
 * Le message d'un push Pub/Sub : `message.data` est le JSON de la
 * notification, en base64. Rend `null` pour ce qui ne se lit pas.
 */
export function parsePushMessage(raw: unknown): GooglePlayNotification | null {
  const data = ((raw ?? {}) as { message?: { data?: unknown } }).message?.data;
  if (typeof data !== "string") return null;

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(Buffer.from(data, "base64").toString("utf8")) as Record<string, unknown>;
  } catch {
    return null;
  }
  const packageName = stringOf(body["packageName"]);
  if (!packageName) return null;

  const subscription = (body["subscriptionNotification"] ?? null) as Record<string, unknown> | null;
  const voided = (body["voidedPurchaseNotification"] ?? null) as Record<string, unknown> | null;
  const subscriptionToken = stringOf(subscription?.["purchaseToken"]);
  const voidedToken = stringOf(voided?.["purchaseToken"]);

  return {
    packageName,
    eventTime: dateOf(Number(body["eventTimeMillis"])) ?? new Date(),
    subscription:
      subscription && subscriptionToken
        ? { notificationType: Number(subscription["notificationType"]), purchaseToken: subscriptionToken }
        : null,
    voided:
      voided && voidedToken
        ? {
            purchaseToken: voidedToken,
            orderId: stringOf(voided["orderId"]),
            productType: typeof voided["productType"] === "number" ? voided["productType"] : null,
          }
        : null,
    isTest: body["testNotification"] !== undefined,
  };
}

function stringOf(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

function dateOf(value: unknown): Date | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  if (typeof value === "number" && !Number.isFinite(value)) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** `{ units: "4", nanos: 990000000 }` → 499. */
function centsOf(money: Record<string, unknown> | null): number | null {
  if (!money) return null;
  const units = Number(money["units"] ?? 0);
  const nanos = Number(money["nanos"] ?? 0);
  if (!Number.isFinite(units) || !Number.isFinite(nanos)) return null;
  return Math.round(units * 100 + nanos / 10_000_000);
}
