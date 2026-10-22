import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { androidIntentUrl } from "./invitePage.js";

/**
 * Le retour de « Continuer avec Apple » **sur Android** (lot B2, 22/10/2026).
 *
 * Android n'a pas de feuille Apple du système : l'app ouvre la page
 * d'autorisation d'Apple dans un Custom Tab (`AppleSignInService.kt`), avec le
 * Services ID pour `client_id`, `response_mode=form_post` et
 * `response_type=code id_token`. Apple n'accepte en adresse de retour qu'une
 * URL `https://` déclarée sur le Services ID — pas le schéma privé de l'app.
 * Il poste donc sa réponse **ici**, et cette route ne fait que la relayer à
 * l'app par `memobook://auth/apple?…`.
 *
 * Elle ne vérifie rien et n'ouvre aucune session : le jeton repart vers l'app,
 * qui l'envoie à `POST /v1/auth/apple` avec le nonce **en clair** qu'elle a
 * gardé — exactement comme l'iPhone. C'est là que la signature, l'audience (le
 * Services ID, accepté à côté du bundle ID) et le nonce sont contrôlés. Relayer
 * un jeton falsifié n'apprend rien à personne : il serait refusé là-bas.
 *
 * - **Le `state`** est tiré par l'app et recopié par Apple. L'app refuse un
 *   retour dont le `state` n'est pas celui de sa tentative en cours : c'est ce
 *   qui empêche une page tierce de lui faire avaler un jeton qu'elle n'a pas
 *   demandé. Ici, on exige seulement qu'il soit là.
 * - **Le `user`** — le nom et l'adresse — n'est posté par Apple qu'**au tout
 *   premier consentement**, jamais ensuite. Le perdre ici, c'est un compte
 *   sans nom pour toujours : il repart avec le jeton, champ par champ.
 * - **Le `code`** est ignoré : l'échanger demanderait un secret client signé
 *   par une clé Apple, et le jeton d'identité suffit à ouvrir la session.
 *
 * Le jeton d'identité est un secret le temps de l'échange : la route ne
 * journalise pas ses requêtes (`logLevel: "warn"`), et la page n'est ni mise
 * en cache, ni citée en `Referer`.
 */

export const APPLE_WEB_CALLBACK_PATH = "/v1/auth/apple/callback";

/** Ce qu'Apple poste, en `application/x-www-form-urlencoded`. */
interface AppleFormPost {
  id_token?: string;
  code?: string;
  state?: string;
  user?: string;
  error?: string;
}

/** Ce que l'app reçoit dans `memobook://auth/apple?…` — lu par `AppleWebReturn.kt`. */
export type AppleWebReturn =
  | {
      idToken: string;
      state: string;
      firstName: string | null;
      lastName: string | null;
      email: string | null;
    }
  | { error: string; state: string | null };

/**
 * Traduit le corps posté par Apple. Les noms des paramètres de l'app sont en
 * `snake_case`, comme ceux d'Apple, pour qu'un lien se lise d'un coup d'œil.
 */
export function readApplePost(body: AppleFormPost): AppleWebReturn {
  const state = nonEmpty(body.state);
  // `user_cancelled_authorize` quand on referme la page d'Apple : l'app le
  // tait, comme la feuille d'iOS refermée.
  const error = nonEmpty(body.error);
  if (error) return { error, state };

  const idToken = nonEmpty(body.id_token);
  if (!idToken || !state) return { error: "invalid_request", state };

  const user = parseUser(body.user);
  return { idToken, state, ...user };
}

/** Le `user` d'Apple : `{"name":{"firstName","lastName"},"email"}`, en JSON dans un champ de formulaire. */
function parseUser(raw: string | undefined): { firstName: string | null; lastName: string | null; email: string | null } {
  const empty = { firstName: null, lastName: null, email: null };
  if (!raw) return empty;
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null) return empty;
    const record = parsed as { name?: { firstName?: unknown; lastName?: unknown }; email?: unknown };
    return {
      firstName: text(record.name?.firstName, 100),
      lastName: text(record.name?.lastName, 100),
      email: text(record.email, 254),
    };
  } catch {
    // Un `user` illisible ne doit pas coûter la connexion : le jeton suffit.
    return empty;
  }
}

/** Le chemin et la requête de l'app, sans le schéma : `auth/apple?…`. */
export function appleReturnPath(result: AppleWebReturn): string {
  const params = new URLSearchParams();
  if ("error" in result) {
    params.set("error", result.error);
    if (result.state) params.set("state", result.state);
  } else {
    params.set("id_token", result.idToken);
    params.set("state", result.state);
    if (result.firstName) params.set("first_name", result.firstName);
    if (result.lastName) params.set("last_name", result.lastName);
    if (result.email) params.set("email", result.email);
  }
  // `URLSearchParams` écrit les espaces en `+` ; `%20` se lit pareil partout,
  // y compris par `java.net.URI`, qui ne décode pas le `+`.
  return `auth/apple?${params.toString().replaceAll("+", "%20")}`;
}

function renderReturnPage(result: AppleWebReturn): string {
  const path = appleReturnPath(result);
  const appUrl = `memobook://${path}`;
  const failed = "error" in result;
  const title = failed ? "Retour à MemoBook" : "Connexion avec Apple";
  const message = failed
    ? "La connexion avec Apple n’a pas abouti. On te ramène dans MemoBook."
    : "C’est bon : on te ramène dans MemoBook pour finir de te connecter.";
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<title>${title}</title>
<style>
  body { margin:0; background:#FCF2E9; color:#2D231A;
    font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif; }
  main { max-width:480px; margin:32px auto; padding:0 16px; }
  .card { background:#FFFCF8; border-radius:20px; padding:32px 24px; }
  h1 { margin:0 0 16px; font-size:22px; line-height:28px; }
  p { margin:0 0 16px; font-size:15px; line-height:22px; }
  .button { display:block; text-align:center; background:#28654B; color:#FFFCF8; text-decoration:none;
    font-size:15px; font-weight:600; line-height:20px; padding:14px 28px; border-radius:12px; margin:24px 0 0; }
</style>
<script>
  // Chrome n'ouvre une app que par un \`intent://\` ; ailleurs, le schéma tel quel.
  var target = ${scriptString(appUrl)};
  if (/Android/.test(navigator.userAgent)) target = ${scriptString(androidIntentUrl(path))};
  window.addEventListener("load", function () {
    document.getElementById("open").href = target;
    window.location.replace(target);
  });
</script>
</head>
<body>
<main><div class="card">
<h1>${title}</h1>
<p>${message}</p>
<a class="button" id="open" href="${escapeHtml(appUrl)}">Ouvrir MemoBook</a>
</div></main>
</body>
</html>`;
}

export async function registerAppleWebSignInRoutes(
  app: FastifyInstance,
  context: AppContext,
): Promise<void> {
  // Une portée à part, pour le seul corps qu'Apple sait poster : le reste de
  // l'API continue de refuser tout ce qui n'est pas du JSON.
  await app.register(async (scope) => {
    scope.addContentTypeParser(
      "application/x-www-form-urlencoded",
      { parseAs: "string" },
      (_request, body, done) => {
        done(null, Object.fromEntries(new URLSearchParams(body as string)));
      },
    );

    scope.post<{ Body: AppleFormPost | undefined }>(
      APPLE_WEB_CALLBACK_PATH,
      // Le corps porte le jeton d'identité : rien de cette requête ne va dans
      // les logs, comme `/password/reset` pour son secret.
      { logLevel: "warn" },
      async (request, reply) => {
        // Coupé tant que le Services ID n'est pas posé : sans lui, le jeton
        // relayé serait de toute façon refusé par `/v1/auth/apple`.
        if (!context.env.APPLE_SERVICES_ID) {
          return reply.code(404).send({ error: "not_found" });
        }
        const result = readApplePost(request.body ?? {});
        return reply
          .header("Cache-Control", "no-store")
          .header("Referrer-Policy", "no-referrer")
          .type("text/html; charset=utf-8")
          .send(renderReturnPage(result));
      },
    );
  });
}

function nonEmpty(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

/** Les mêmes bornes que `POST /v1/auth/apple` (`appleBody`), pour que le relais passe. */
function text(value: unknown, max: number): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim().slice(0, max) : null;
}

/** Une chaîne JavaScript sûre dans un `<script>` : `JSON.stringify` n'échappe pas `</`. */
function scriptString(value: string): string {
  return JSON.stringify(value).replaceAll("<", "\\u003c");
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
