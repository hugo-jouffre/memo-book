import { readdirSync, readFileSync } from "node:fs";
import {
  AutoRenewStatus,
  Environment,
  SignedDataVerifier,
  Status,
  VerificationException,
  VerificationStatus,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import type { Env } from "../env.js";

/**
 * L'App Store : ce qu'Apple signe, vérifié avant qu'on y croie.
 *
 * **Tout ce qui ouvre l'abonnement passe par ici**, que ça vienne de l'app
 * (`POST /v1/subscriptions/app-store`, juste après l'achat) ou d'Apple
 * (`POST /v1/webhooks/app-store`, à chaque renouvellement). Une transaction est
 * un JWS : un JSON signé par une chaîne de certificats qui remonte au
 * certificat racine d'Apple, rangé dans `certs/apple/`. Sans cette vérification,
 * n'importe qui pourrait poster un JSON qui dit « j'ai payé ».
 *
 * Trois pièges, et le fichier est organisé autour d'eux :
 *
 * 1. **App Review achète en sandbox, contre le serveur de production.** Un
 *    serveur qui ne connaît que la production refuse l'achat du testeur, et
 *    Apple rejette l'app pour « achat qui ne marche pas ». On garde donc un
 *    vérificateur par environnement, et c'est la transaction qui dit lequel
 *    prendre — la bibliothèque revérifie ensuite qu'elle a dit vrai.
 * 2. **Une transaction Xcode n'est pas signée.** La bibliothèque saute la
 *    vérification pour `Xcode` et `LocalTesting` ; ces environnements ne sont
 *    donc acceptés que si `APP_STORE_ALLOW_XCODE` l'autorise, et `env.ts` refuse
 *    cette valeur en production.
 * 3. **Le prix est en millièmes.** `4990` veut dire 4,99 €.
 */

/** Une transaction App Store vérifiée, dans nos mots. */
export interface AppStoreTransaction {
  transactionId: string;
  /** La première transaction de l'abonnement — elle survit aux réabonnements. */
  originalTransactionId: string;
  productId: string;
  /** L'identifiant du compte MemoBook que l'app a posé à l'achat, s'il y en a un. */
  appAccountToken: string | null;
  purchasedAt: Date;
  /** La fin de la période payée — le mois, ou la semaine d'un ancien abonné. */
  expiresAt: Date | null;
  /** Remboursée ou révoquée : la période ne compte plus. */
  revokedAt: Date | null;
  /** TTC, en centimes. Nul pour les transactions qui ne le portaient pas. */
  priceCents: number | null;
  currency: string | null;
  environment: string;
  signedAt: Date;
}

/** Ce qu'Apple prévoit pour la suite de l'abonnement. */
export interface AppStoreRenewal {
  /** Le renouvellement est-il encore armé ? */
  autoRenews: boolean;
  /** La fin du délai de grâce, quand un prélèvement a échoué. */
  gracePeriodEndsAt: Date | null;
}

/** L'état de l'abonnement au moment où Apple a signé la notification. */
export type AppStoreStatus = "active" | "expired" | "billing_retry" | "grace_period" | "revoked";

/** Une notification App Store Server, version 2, vérifiée. */
export interface AppStoreNotification {
  notificationId: string;
  type: string;
  subtype: string | null;
  signedAt: Date;
  transaction: AppStoreTransaction | null;
  renewal: AppStoreRenewal | null;
  status: AppStoreStatus | null;
}

export interface AppStoreVerifier {
  /** Vérifie une transaction envoyée par l'app (`Transaction.jwsRepresentation`). */
  verifyTransaction(signedTransaction: string): Promise<AppStoreTransaction>;
  /** Vérifie le `signedPayload` d'une notification, et ce qu'il contient. */
  verifyNotification(signedPayload: string): Promise<AppStoreNotification>;
}

/**
 * Une donnée qu'on refuse de croire. **Toujours un 400**, jamais un 500 : un JWS
 * invalide n'est pas une panne, c'est un appel qu'on rejette. Apple rejoue tout
 * ce qui n'est pas un 200, 4xx compris — une notification refusée reviendra
 * donc, et sera refusée de nouveau sans rien écrire.
 */
export class AppStoreVerificationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AppStoreVerificationError";
  }
}

/** Les états que porte `data.status`, dans nos mots. */
const STATUS_NAMES: Record<number, AppStoreStatus> = {
  [Status.ACTIVE]: "active",
  [Status.EXPIRED]: "expired",
  [Status.BILLING_RETRY]: "billing_retry",
  [Status.BILLING_GRACE_PERIOD]: "grace_period",
  [Status.REVOKED]: "revoked",
};

/** Où vivent les certificats racine, depuis `src/services` comme depuis `dist/services`. */
const ROOT_CERTIFICATES_DIR = new URL("../../certs/apple/", import.meta.url);

export class AppleAppStoreVerifier implements AppStoreVerifier {
  private readonly verifiers = new Map<string, SignedDataVerifier>();

  constructor(options: {
    bundleId: string;
    appAppleId?: number;
    allowXcode: boolean;
    rootCertificates: Buffer[];
  }) {
    const { bundleId, appAppleId, allowXcode, rootCertificates } = options;
    // `true` : contrôle de révocation et date du jour. C'est ce qu'Apple
    // recommande en production, et les certificats intermédiaires sont mis en
    // cache — une vérification par heure au plus, pas une par achat.
    const make = (environment: Environment, appleId?: number) =>
      new SignedDataVerifier(rootCertificates, true, environment, bundleId, appleId);

    this.verifiers.set(Environment.SANDBOX, make(Environment.SANDBOX));
    // La production exige l'identifiant numérique de l'app : sans lui, la
    // bibliothèque refuserait tout. Absent, on n'accepte que le sandbox.
    if (appAppleId !== undefined) {
      this.verifiers.set(Environment.PRODUCTION, make(Environment.PRODUCTION, appAppleId));
    }
    if (allowXcode) {
      this.verifiers.set(Environment.XCODE, make(Environment.XCODE));
      this.verifiers.set(Environment.LOCAL_TESTING, make(Environment.LOCAL_TESTING));
    }
  }

  async verifyTransaction(signedTransaction: string): Promise<AppStoreTransaction> {
    const claimed = peekClaims(signedTransaction)?.["environment"];
    const verifier = this.verifierFor(claimed);
    return toTransaction(await guarded(() => verifier.verifyAndDecodeTransaction(signedTransaction)));
  }

  async verifyNotification(signedPayload: string): Promise<AppStoreNotification> {
    const claims = peekClaims(signedPayload);
    const data = claims?.["data"] as Record<string, unknown> | undefined;
    const summary = claims?.["summary"] as Record<string, unknown> | undefined;
    const verifier = this.verifierFor(data?.["environment"] ?? summary?.["environment"]);

    const payload = await guarded(() => verifier.verifyAndDecodeNotification(signedPayload));
    const signedTransaction = payload.data?.signedTransactionInfo;
    const signedRenewal = payload.data?.signedRenewalInfo;

    return {
      notificationId: payload.notificationUUID ?? "",
      type: payload.notificationType ?? "",
      subtype: payload.subtype ?? null,
      signedAt: new Date(payload.signedDate ?? Date.now()),
      transaction: signedTransaction
        ? toTransaction(await guarded(() => verifier.verifyAndDecodeTransaction(signedTransaction)))
        : null,
      renewal: signedRenewal
        ? toRenewal(await guarded(() => verifier.verifyAndDecodeRenewalInfo(signedRenewal)))
        : null,
      status: payload.data?.status !== undefined ? (STATUS_NAMES[payload.data.status] ?? null) : null,
    };
  }

  /**
   * Le vérificateur de l'environnement que la donnée **annonce**. Ce n'est pas
   * lui faire confiance : la bibliothèque recompare l'environnement signé à
   * celui du vérificateur, et refuse s'ils diffèrent.
   */
  private verifierFor(environment: unknown): SignedDataVerifier {
    const verifier = typeof environment === "string" ? this.verifiers.get(environment) : undefined;
    if (!verifier) {
      throw new AppStoreVerificationError(
        `Environnement App Store refusé par ce serveur : ${String(environment)}.`,
      );
    }
    return verifier;
  }
}

/** Le vérificateur d'un serveur sans configuration App Store : il refuse tout, et dit pourquoi. */
class UnconfiguredAppStoreVerifier implements AppStoreVerifier {
  constructor(private readonly reason: string) {}

  async verifyTransaction(): Promise<AppStoreTransaction> {
    throw new AppStoreVerificationError(this.reason);
  }

  async verifyNotification(): Promise<AppStoreNotification> {
    throw new AppStoreVerificationError(this.reason);
  }
}

export function createAppStoreVerifier(env: Env): AppStoreVerifier {
  if (env.APPLE_BUNDLE_ID === "") {
    return new UnconfiguredAppStoreVerifier("L'App Store n'est pas configuré : APPLE_BUNDLE_ID est vide.");
  }

  const rootCertificates = readRootCertificates();
  if (rootCertificates.length === 0) {
    // Le serveur démarre quand même : un abonnement en panne ne doit pas
    // emporter le reste de l'API. Mais l'achat le dira, en toutes lettres.
    return new UnconfiguredAppStoreVerifier(
      "Aucun certificat racine Apple dans backend/certs/apple/ — l'image Docker l'a-t-elle copié ?",
    );
  }

  return new AppleAppStoreVerifier({
    bundleId: env.APPLE_BUNDLE_ID,
    ...(env.APP_STORE_APP_APPLE_ID === undefined ? {} : { appAppleId: env.APP_STORE_APP_APPLE_ID }),
    allowXcode: env.APP_STORE_ALLOW_XCODE,
    rootCertificates,
  });
}

/** Les certificats `.cer` (DER) de `certs/apple/`. Vide si le dossier manque. */
export function readRootCertificates(): Buffer[] {
  try {
    return readdirSync(ROOT_CERTIFICATES_DIR)
      .filter((name) => name.endsWith(".cer"))
      .map((name) => readFileSync(new URL(name, ROOT_CERTIFICATES_DIR)));
  } catch {
    return [];
  }
}

/**
 * Les revendications d'un JWS, lues **sans vérifier la signature** — seulement
 * pour savoir quel vérificateur lui présenter. Rien de ce qui sort d'ici n'est
 * cru : tout repasse par `SignedDataVerifier`.
 */
function peekClaims(jws: string): Record<string, unknown> | null {
  const payload = jws.split(".")[1];
  if (!payload) return null;
  try {
    const decoded: unknown = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    return decoded !== null && typeof decoded === "object" ? (decoded as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/** Traduit l'exception de la bibliothèque en refus lisible. */
async function guarded<T>(verify: () => Promise<T>): Promise<T> {
  try {
    return await verify();
  } catch (cause) {
    if (cause instanceof VerificationException) {
      throw new AppStoreVerificationError(
        `Signature App Store refusée (${VerificationStatus[cause.status] ?? cause.status}).`,
      );
    }
    throw cause;
  }
}

function toTransaction(decoded: JWSTransactionDecodedPayload): AppStoreTransaction {
  const { transactionId, originalTransactionId, productId, purchaseDate, environment } = decoded;
  if (!transactionId || !originalTransactionId || !productId || !purchaseDate || !environment) {
    throw new AppStoreVerificationError("Transaction App Store incomplète.");
  }

  return {
    transactionId,
    originalTransactionId,
    productId,
    appAccountToken: decoded.appAccountToken?.toLowerCase() ?? null,
    purchasedAt: new Date(purchaseDate),
    expiresAt: decoded.expiresDate ? new Date(decoded.expiresDate) : null,
    revokedAt: decoded.revocationDate ? new Date(decoded.revocationDate) : null,
    // Des millièmes vers des centimes : 4990 → 499.
    priceCents: decoded.price === undefined ? null : Math.round(decoded.price / 10),
    currency: decoded.currency ?? null,
    environment,
    signedAt: new Date(decoded.signedDate ?? purchaseDate),
  };
}

function toRenewal(decoded: JWSRenewalInfoDecodedPayload): AppStoreRenewal {
  return {
    autoRenews: decoded.autoRenewStatus === AutoRenewStatus.ON,
    gracePeriodEndsAt: decoded.gracePeriodExpiresDate ? new Date(decoded.gracePeriodExpiresDate) : null,
  };
}
