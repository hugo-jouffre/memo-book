import { createHash } from "node:crypto";
import { createRemoteJWKSet, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from "jose";
import type { Env } from "../env.js";
import { HttpError } from "../lib/httpError.js";

/**
 * Vérification des jetons d'identité d'Apple et de Google.
 *
 * > Important : c'est **le** point de sécurité de toute l'authentification.
 * > Le client envoie une chaîne ; rien n'empêche n'importe qui d'en fabriquer
 * > une. Ce qui identifie quelqu'un, c'est la signature du jeton par la clé
 * > privée du fournisseur, vérifiée ici contre ses clés publiques.
 *
 * Quatre choses sont contrôlées, et il faut les quatre :
 *
 * - **la signature**, contre le jeu de clés publiques du fournisseur ;
 * - **l'émetteur** (`iss`), sinon un jeton d'un autre fournisseur passerait ;
 * - **l'audience** (`aud`), sinon un jeton Apple émis pour *une autre app*
 *   ouvrirait un compte chez nous — c'est l'erreur classique ;
 * - **l'expiration**, faite par `jwtVerify`.
 *
 * Pour Apple s'ajoute le **nonce** : l'app tire un secret, en envoie
 * l'empreinte à Apple, qui la recopie dans le jeton. On rehache le secret que
 * l'app nous transmet et on compare. Sans ça, un jeton authentique intercepté
 * ailleurs resterait rejouable ici.
 */

export interface VerifiedIdentity {
  provider: "apple" | "google";
  /** Le `sub` : identifiant stable de la personne chez ce fournisseur. */
  subject: string;
  email: string | null;
  /** Le fournisseur certifie-t-il cette adresse ? Conditionne le rattachement. */
  emailVerified: boolean;
}

const APPLE_ISSUER = "https://appleid.apple.com";
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];

// `createRemoteJWKSet` garde les clés en mémoire et ne rappelle le fournisseur
// que lorsqu'un `kid` inconnu apparaît — c'est-à-dire à chaque rotation, et
// pas à chaque connexion. Les jeux sont donc créés une fois, pas par requête.
const appleKeys = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`));
const googleKeys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));

export interface SocialVerifier {
  verifyApple(identityToken: string, nonce: string | null): Promise<VerifiedIdentity>;
  verifyGoogle(identityToken: string): Promise<VerifiedIdentity>;
}

/**
 * Les jeux de clés publiques, remplaçables par des clés locales dans les
 * tests : la vérification elle-même se teste alors sans réseau.
 */
export interface SocialKeySets {
  apple?: KeySet;
  google?: KeySet;
}

export function createSocialVerifier(
  env: Pick<Env, "APPLE_BUNDLE_ID" | "APPLE_SERVICES_ID" | "GOOGLE_IOS_CLIENT_ID" | "GOOGLE_WEB_CLIENT_ID">,
  keys: SocialKeySets = {},
): SocialVerifier {
  return {
    async verifyApple(identityToken, nonce) {
      requireConfigured(env.APPLE_BUNDLE_ID, "APPLE_BUNDLE_ID");

      // Deux audiences légitimes : le bundle ID pour la feuille Apple de
      // l'iPhone, le Services ID pour la page web d'Apple qu'ouvre Android
      // (lot B2). Le reste est identique — même émetteur, mêmes clés, même
      // nonce — et le `sub` aussi, tant que le Services ID est groupé sous
      // l'App ID : c'est ce qui retrouve le même compte des deux côtés.
      const audiences = [env.APPLE_BUNDLE_ID, env.APPLE_SERVICES_ID].filter(
        (value) => value.length > 0,
      );
      const { payload } = await verify(identityToken, keys.apple ?? appleKeys, {
        issuer: APPLE_ISSUER,
        audience: audiences,
      });

      // Apple range dans le jeton l'empreinte SHA-256 du nonce, en
      // hexadécimal. Le jeton n'en porte pas si l'app n'en a pas demandé —
      // auquel cas on refuse plutôt que d'accepter un jeton rejouable.
      const tokenNonce = typeof payload["nonce"] === "string" ? payload["nonce"] : null;
      if (!tokenNonce || !nonce || sha256Hex(nonce) !== tokenNonce) {
        throw HttpError.unauthorized("Jeton Apple invalide.");
      }

      return toIdentity("apple", payload);
    },

    async verifyGoogle(identityToken) {
      const audiences = [env.GOOGLE_IOS_CLIENT_ID, env.GOOGLE_WEB_CLIENT_ID].filter(
        (value): value is string => value.length > 0,
      );
      if (audiences.length === 0) {
        throw new Error(
          "Aucun client OAuth Google configuré (GOOGLE_IOS_CLIENT_ID / GOOGLE_WEB_CLIENT_ID).",
        );
      }

      const { payload } = await verify(identityToken, keys.google ?? googleKeys, {
        // `jose` accepte une liste : l'app iOS et un futur client web ont
        // chacun leur identifiant, et les deux sont légitimes.
        issuer: GOOGLE_ISSUERS,
        audience: audiences,
      });

      return toIdentity("google", payload);
    },
  };
}

type KeySet = JWTVerifyGetKey;

async function verify(
  token: string,
  keys: KeySet,
  options: { issuer: string | string[]; audience: string | string[] },
) {
  try {
    return await jwtVerify(token, keys, options);
  } catch {
    // Le détail — signature, expiration, audience — n'apprendrait rien à
    // l'utilisateur, et renseignerait un attaquant sur ce qui a échoué.
    throw HttpError.unauthorized("Jeton d'identité invalide ou expiré.");
  }
}

function toIdentity(
  provider: VerifiedIdentity["provider"],
  payload: JWTPayload,
): VerifiedIdentity {
  const subject = payload.sub;
  if (!subject) throw HttpError.unauthorized("Jeton d'identité sans sujet.");

  const email = typeof payload["email"] === "string" ? payload["email"] : null;

  // Les deux fournisseurs rendent parfois `email_verified` en chaîne plutôt
  // qu'en booléen. Apple le fait pour les adresses relais.
  const raw = payload["email_verified"];
  const emailVerified = raw === true || raw === "true";

  return { provider, subject, email, emailVerified };
}

function requireConfigured(value: string, name: string): void {
  if (!value) throw new Error(`${name} n'est pas configuré.`);
}

function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
