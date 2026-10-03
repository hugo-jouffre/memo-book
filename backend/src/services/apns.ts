import { connect, constants, type ClientHttp2Session } from "node:http2";
import { importPKCS8, SignJWT, type CryptoKey } from "jose";
import type { Logger } from "pino";
import type { Env } from "../env.js";

/**
 * L'envoi d'une notification à un téléphone, par **APNs** — le service de
 * notifications d'Apple. Voir `docs/notifications.md`.
 *
 * Pas de bibliothèque : APNs est une requête HTTP/2 signée d'un JWT, et Node
 * sait faire les deux (`node:http2`, `jose` déjà là pour Apple et Google).
 * Une dépendance de plus pour cinquante lignes aurait surtout ajouté une
 * version à suivre.
 *
 * **Le contrat avec l'app** : `aps.alert` porte le titre et le texte, et deux
 * clés à côté d'`aps` disent quoi faire au toucher — `link`, un lien
 * `memobook://` que `NotificationLink` sait lire, et `deliveryId`, que l'app
 * renvoie à `POST /v1/notifications/:id/opened`. Renommer l'une, c'est casser
 * le toucher sur tous les téléphones déjà livrés.
 */

export type PushEnvironment = "sandbox" | "production";

export interface PushDestination {
  token: string;
  environment: PushEnvironment;
}

export interface PushMessage {
  /** L'identifiant de la ligne `notification_deliveries`, renvoyé à l'ouverture. */
  deliveryId: string;
  title: string;
  body: string;
  /** Le lien `memobook://` à ouvrir au toucher. */
  link: string | null;
  /**
   * Regroupe les notifications d'un même voyage dans le centre de
   * notifications (`thread-id`). Celles du compte (vacances, renouvellement) restent
   * entre elles.
   */
  threadId: string;
}

/**
 * Ce qu'Apple a fait d'un envoi.
 *
 * - `sent` : accepté. Ce n'est pas « affiché » — un téléphone éteint le
 *   recevra plus tard, un téléphone dont la personne a coupé les
 *   notifications ne le montrera jamais —, mais c'est tout ce qu'on saura.
 * - `invalid_token` : ce jeton ne mène plus nulle part (app désinstallée,
 *   jeton d'un autre environnement). On l'oublie.
 * - `failed` : tout le reste — réseau, clé refusée, Apple saturé. Le jeton est
 *   gardé, et l'envoi se retentera à la passe suivante.
 */
export type PushOutcome =
  | { kind: "sent" }
  | { kind: "invalid_token"; reason: string }
  | { kind: "failed"; reason: string };

export interface PushSender {
  /**
   * `false` quand rien ne peut partir — la production sans clé. La tâche
   * d'envoi ne marque alors rien comme envoyé : la première passe après la
   * pose de la clé reprendra ce qui était dû ce jour-là.
   */
  readonly enabled: boolean;
  send(destination: PushDestination, message: PushMessage): Promise<PushOutcome>;
  /** Ferme les connexions ouvertes. Appelé à la fin de chaque passe. */
  close(): Promise<void>;
}

/** La charge utile telle qu'APNs la reçoit — et telle que l'app la lit. */
export function apnsPayload(message: PushMessage): Record<string, unknown> {
  return {
    aps: {
      alert: { title: message.title, body: message.body },
      sound: "default",
      "thread-id": message.threadId,
    },
    link: message.link,
    deliveryId: message.deliveryId,
  };
}

const APNS_HOSTS: Record<PushEnvironment, string> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

/**
 * Le JWT d'APNs vit une heure, et Apple refuse qu'on en signe un nouveau plus
 * d'une fois toutes les vingt minutes (`TooManyProviderTokenUpdates`). On le
 * garde cinquante minutes : assez longtemps pour ne pas en abuser, assez peu
 * pour ne jamais présenter un jeton expiré.
 */
const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000;

/** Une notification non délivrée au bout d'un jour ne veut plus rien dire. */
const EXPIRATION_SECONDS = 24 * 60 * 60;

const REQUEST_TIMEOUT_MS = 15_000;

/** Les réponses d'Apple qui disent que le jeton, lui, est mort. */
const DEAD_TOKEN_REASONS = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]);

export interface ApnsCredentials {
  keyId: string;
  teamId: string;
  /** Le contenu du `.p8`. */
  privateKey: string;
  /** L'identifiant de l'app, `com.memobook.app`. */
  topic: string;
}

export class ApnsPushSender implements PushSender {
  readonly enabled = true;

  private signingKey: Promise<CryptoKey> | null = null;
  private providerToken: { value: string; signedAt: number } | null = null;
  private readonly sessions = new Map<PushEnvironment, ClientHttp2Session>();

  constructor(
    private readonly credentials: ApnsCredentials,
    private readonly logger: Pick<Logger, "warn">,
  ) {}

  async send(destination: PushDestination, message: PushMessage): Promise<PushOutcome> {
    let authorization: string;
    try {
      authorization = `bearer ${await this.currentProviderToken()}`;
    } catch (cause) {
      return { kind: "failed", reason: `Clé APNs illisible : ${describe(cause)}` };
    }

    const body = JSON.stringify(apnsPayload(message));

    return new Promise<PushOutcome>((resolve) => {
      let session: ClientHttp2Session;
      try {
        session = this.session(destination.environment);
      } catch (cause) {
        resolve({ kind: "failed", reason: describe(cause) });
        return;
      }

      const request = session.request({
        [constants.HTTP2_HEADER_METHOD]: "POST",
        [constants.HTTP2_HEADER_PATH]: `/3/device/${destination.token}`,
        authorization,
        "apns-topic": this.credentials.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + EXPIRATION_SECONDS),
        "content-type": "application/json",
      });

      let status = 0;
      let response = "";
      request.setEncoding("utf8");
      request.setTimeout(REQUEST_TIMEOUT_MS, () => {
        request.close(constants.NGHTTP2_CANCEL);
        resolve({ kind: "failed", reason: "APNs n'a pas répondu à temps." });
      });
      request.on("response", (headers) => {
        status = Number(headers[constants.HTTP2_HEADER_STATUS] ?? 0);
      });
      request.on("data", (chunk: string) => {
        response += chunk;
      });
      request.on("error", (cause) => resolve({ kind: "failed", reason: describe(cause) }));
      request.on("end", () => resolve(this.interpret(status, response)));
      request.end(body);
    });
  }

  async close(): Promise<void> {
    for (const session of this.sessions.values()) session.close();
    this.sessions.clear();
  }

  private interpret(status: number, response: string): PushOutcome {
    if (status === 200) return { kind: "sent" };

    let reason = `HTTP ${status}`;
    try {
      reason = (JSON.parse(response) as { reason?: string }).reason ?? reason;
    } catch {
      // Corps vide ou illisible : le statut suffit.
    }

    if (status === 410 || DEAD_TOKEN_REASONS.has(reason)) {
      return { kind: "invalid_token", reason };
    }
    if (reason === "InvalidProviderToken" || reason === "ExpiredProviderToken") {
      // La clé, l'équipe ou l'identifiant de clé sont faux — ou le jeton a
      // vieilli. On en signe un neuf au prochain envoi.
      this.providerToken = null;
      this.logger.warn(
        { reason },
        "APNs refuse la clé du serveur : vérifier APNS_KEY_ID, APNS_TEAM_ID et APNS_PRIVATE_KEY.",
      );
    }
    return { kind: "failed", reason };
  }

  private session(environment: PushEnvironment): ClientHttp2Session {
    const existing = this.sessions.get(environment);
    if (existing && !existing.closed && !existing.destroyed) return existing;

    const session = connect(APNS_HOSTS[environment]);
    // Une session qui tombe — Apple la ferme au bout d'un moment d'inactivité
    // — est simplement oubliée : la suivante se rouvrira à la demande.
    const forget = () => {
      if (this.sessions.get(environment) === session) this.sessions.delete(environment);
    };
    session.on("error", forget);
    session.on("close", forget);
    session.on("goaway", forget);
    this.sessions.set(environment, session);
    return session;
  }

  private async currentProviderToken(): Promise<string> {
    const now = Date.now();
    if (this.providerToken && now - this.providerToken.signedAt < PROVIDER_TOKEN_TTL_MS) {
      return this.providerToken.value;
    }

    this.signingKey ??= importPKCS8(this.credentials.privateKey, "ES256");
    const value = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: this.credentials.keyId })
      .setIssuer(this.credentials.teamId)
      .setIssuedAt(Math.floor(now / 1000))
      .sign(await this.signingKey);

    this.providerToken = { value, signedAt: now };
    return value;
  }
}

/**
 * Sans clé, hors production : chaque notification est **journalisée** — titre,
 * texte, lien —, et retenue dans `sent` pour que les tests la lisent. Elle
 * « part » : c'est ce qui permet de suivre les règles de bout en bout sur un
 * serveur local, et de les vérifier dans la suite.
 */
export class LoggingPushSender implements PushSender {
  readonly enabled = true;
  readonly sent: { destination: PushDestination; message: PushMessage }[] = [];

  constructor(private readonly logger: Pick<Logger, "info"> | null) {}

  async send(destination: PushDestination, message: PushMessage): Promise<PushOutcome> {
    this.sent.push({ destination, message });
    this.logger?.info(
      { token: `${destination.token.slice(0, 8)}…`, title: message.title, link: message.link },
      `Notification (non envoyée, APNs non configuré) : ${message.body}`,
    );
    return { kind: "sent" };
  }

  async close(): Promise<void> {}
}

/** La production sans clé : rien ne part, et la tâche le sait. */
export class DisabledPushSender implements PushSender {
  readonly enabled = false;

  async send(): Promise<PushOutcome> {
    return { kind: "failed", reason: "APNs n'est pas configuré." };
  }

  async close(): Promise<void> {}
}

/**
 * Le contenu d'un `.p8` tel qu'une variable d'environnement le rend : les
 * retours à la ligne écrits `\n` par Railway redeviennent de vrais retours.
 *
 * Et une clé collée **sans ses lignes d'en-tête** — les quatre lignes du
 * milieu seulement, vu sur Railway le 02/10/2026 — retrouve son armure PEM :
 * sans elle, `importPKCS8` ne la lit pas et rien ne part.
 */
export function normalizePrivateKey(raw: string): string {
  const key = raw.includes("\\n") ? raw.replace(/\\n/g, "\n").trim() : raw.trim();
  if (key === "" || key.includes("-----BEGIN")) return key;
  const body = key.replace(/\s+/g, "").match(/.{1,64}/g)?.join("\n") ?? "";
  return `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`;
}

export function createPushSender(env: Env, logger: Logger): PushSender {
  const configured =
    env.APNS_KEY_ID !== "" && env.APNS_TEAM_ID !== "" && env.APNS_PRIVATE_KEY !== "";

  if (configured) {
    return new ApnsPushSender(
      {
        keyId: env.APNS_KEY_ID,
        teamId: env.APNS_TEAM_ID,
        privateKey: normalizePrivateKey(env.APNS_PRIVATE_KEY),
        topic: env.APPLE_BUNDLE_ID || "com.memobook.app",
      },
      logger,
    );
  }

  if (env.NODE_ENV === "production") return new DisabledPushSender();
  return new LoggingPushSender(env.NODE_ENV === "test" ? null : logger);
}

function describe(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}
