import { importPKCS8, SignJWT, type CryptoKey } from "jose";
import type { Logger } from "pino";
import type { PushDestination, PushMessage, PushOutcome, PushSender } from "./apns.js";

/**
 * L'envoi d'une notification à un téléphone Android, par **Firebase Cloud
 * Messaging** — l'API HTTP v1 (lot B3, 22/10/2026). Voir `docs/notifications.md`.
 *
 * Pas de SDK, comme pour APNs : `firebase-admin` tire des dizaines de
 * dépendances pour deux requêtes. Un compte de service Google signe un JWT
 * (RS256, `jose`), l'échange contre un jeton d'accès OAuth d'une heure, et ce
 * jeton autorise `POST …/messages:send`.
 *
 * **Le contrat avec l'app** : un message **de données seulement** — aucune
 * clé `notification`. Android le remet alors toujours à
 * `MemoBookMessagingService.onMessageReceived`, app ouverte ou non, et c'est
 * l'app qui pose la notification (son canal, son icône, et l'intention qui
 * porte `link` et `deliveryId` jusqu'à `PushNotifications.didOpen`). Avec une
 * clé `notification`, le système l'afficherait lui-même app fermée, sans
 * passer par l'app. Les clés sont celles de la charge APNs : `title`, `body`,
 * `link`, `deliveryId`, plus `threadId` pour regrouper un voyage. Renommer
 * l'une, c'est casser le toucher sur tous les téléphones livrés.
 */

/** Ce qu'il faut garder du JSON du compte de service que Firebase fait télécharger. */
export interface FcmServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
  token_uri?: string;
}

export interface FcmCredentials {
  serviceAccount: FcmServiceAccount;
  projectId: string;
}

/** La charge de données telle que FCM la reçoit — des chaînes seulement. */
export function fcmMessage(token: string, message: PushMessage): Record<string, unknown> {
  const data: Record<string, string> = {
    title: message.title,
    body: message.body,
    deliveryId: message.deliveryId,
    threadId: message.threadId,
  };
  // FCM refuse une valeur nulle : un lien absent est une clé absente, ce que
  // l'app lit de la même façon (`getStringExtra` rend `null`).
  if (message.link) data.link = message.link;

  return {
    message: {
      token,
      data,
      android: {
        // « high » : la notification réveille le téléphone en veille, comme
        // `apns-priority: 10`. Android la rétrograde si l'app n'affiche rien —
        // elle affiche toujours.
        priority: "high",
        // Comme `apns-expiration` : au bout d'un jour, elle ne veut plus rien dire.
        ttl: `${EXPIRATION_SECONDS}s`,
      },
    },
  };
}

const EXPIRATION_SECONDS = 24 * 60 * 60;
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token";
const REQUEST_TIMEOUT_MS = 15_000;

/** Un jeton d'accès renouvelé cinq minutes avant sa fin, jamais présenté expiré. */
const ACCESS_TOKEN_MARGIN_MS = 5 * 60 * 1000;

/**
 * Les codes de FCM qui disent que le jeton, lui, est mort : app désinstallée
 * ou jeton tourné (`UNREGISTERED`), jeton d'un autre projet Firebase
 * (`SENDER_ID_MISMATCH`). `INVALID_ARGUMENT` n'en fait pas partie : il peut
 * aussi viser la charge, et oublier un bon jeton pour une faute du serveur
 * rendrait le téléphone muet jusqu'à sa prochaine entrée dans l'app.
 */
const DEAD_TOKEN_CODES = new Set(["UNREGISTERED", "SENDER_ID_MISMATCH"]);

export class FcmPushSender implements PushSender {
  readonly enabled = true;

  private signingKey: Promise<CryptoKey> | null = null;
  private accessToken: { value: string; expiresAt: number } | null = null;

  constructor(
    private readonly credentials: FcmCredentials,
    private readonly logger: Pick<Logger, "warn">,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  async send(destination: PushDestination, message: PushMessage): Promise<PushOutcome> {
    let authorization: string;
    try {
      authorization = `Bearer ${await this.currentAccessToken()}`;
    } catch (cause) {
      return { kind: "failed", reason: `Compte de service FCM refusé : ${describe(cause)}` };
    }

    const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(this.credentials.projectId)}/messages:send`;
    let response: Response;
    try {
      response = await this.fetcher(url, {
        method: "POST",
        headers: { authorization, "content-type": "application/json" },
        body: JSON.stringify(fcmMessage(destination.token, message)),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (cause) {
      return { kind: "failed", reason: describe(cause) };
    }

    if (response.ok) return { kind: "sent" };
    return this.interpret(response.status, await response.text().catch(() => ""));
  }

  async close(): Promise<void> {}

  private interpret(status: number, text: string): PushOutcome {
    const code = errorCode(text);
    const reason = code ?? `HTTP ${status}`;

    if (code && DEAD_TOKEN_CODES.has(code)) return { kind: "invalid_token", reason };
    if (status === 401 || status === 403) {
      // Jeton d'accès vieilli, ou compte de service sans le rôle FCM : on en
      // redemande un au prochain envoi, et on le dit.
      this.accessToken = null;
      this.logger.warn(
        { reason },
        "FCM refuse le serveur : vérifier FCM_SERVICE_ACCOUNT_JSON et FCM_PROJECT_ID.",
      );
    }
    return { kind: "failed", reason };
  }

  private async currentAccessToken(): Promise<string> {
    const now = Date.now();
    if (this.accessToken && now < this.accessToken.expiresAt - ACCESS_TOKEN_MARGIN_MS) {
      return this.accessToken.value;
    }

    const account = this.credentials.serviceAccount;
    const tokenUri = account.token_uri || DEFAULT_TOKEN_URI;
    this.signingKey ??= importPKCS8(account.private_key, "RS256");
    const issuedAt = Math.floor(now / 1000);
    const assertion = await new SignJWT({ scope: SCOPE })
      .setProtectedHeader({ alg: "RS256", typ: "JWT" })
      .setIssuer(account.client_email)
      .setAudience(tokenUri)
      .setIssuedAt(issuedAt)
      .setExpirationTime(issuedAt + 3600)
      .sign(await this.signingKey);

    const response = await this.fetcher(tokenUri, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status} ${await response.text().catch(() => "")}`.trim());

    const body = (await response.json()) as { access_token?: string; expires_in?: number };
    if (!body.access_token) throw new Error("Pas de jeton d'accès dans la réponse de Google.");
    this.accessToken = { value: body.access_token, expiresAt: now + (body.expires_in ?? 3600) * 1000 };
    return body.access_token;
  }
}

/**
 * Le code d'erreur FCM d'une réponse : `details[].errorCode` quand il est là
 * (`UNREGISTERED`), sinon le `status` Google (`INVALID_ARGUMENT`).
 */
function errorCode(text: string): string | null {
  try {
    const parsed = JSON.parse(text) as {
      error?: { status?: string; details?: { "@type"?: string; errorCode?: string }[] };
    };
    const detail = parsed.error?.details?.find((entry) => typeof entry.errorCode === "string");
    return detail?.errorCode ?? parsed.error?.status ?? null;
  } catch {
    return null;
  }
}

/**
 * Lit les variables de FCM. `null` quand FCM est coupé — JSON vide —, et une
 * erreur lisible quand il est posé mais faux : le serveur démarre quand même,
 * FCM coupé, et le dit.
 */
export function readFcmCredentials(
  serviceAccountJson: string,
  projectId: string,
): { credentials: FcmCredentials } | { error: string } | null {
  const raw = serviceAccountJson.trim();
  if (raw === "") return null;

  let parsed: Partial<FcmServiceAccount>;
  try {
    parsed = JSON.parse(raw) as Partial<FcmServiceAccount>;
  } catch {
    return { error: "FCM_SERVICE_ACCOUNT_JSON n'est pas un JSON lisible." };
  }
  if (typeof parsed.client_email !== "string" || typeof parsed.private_key !== "string") {
    return { error: "FCM_SERVICE_ACCOUNT_JSON n'a pas de client_email ni de private_key." };
  }

  const project = projectId.trim() || parsed.project_id || "";
  if (project === "") return { error: "FCM_PROJECT_ID est vide, et le compte de service n'a pas de project_id." };

  return {
    credentials: {
      serviceAccount: {
        client_email: parsed.client_email,
        // Une clé recopiée à la main garde parfois ses `\n` écrits.
        private_key: parsed.private_key.replace(/\\n/g, "\n"),
        project_id: parsed.project_id,
        token_uri: parsed.token_uri,
      },
      projectId: project,
    },
  };
}

function describe(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}
