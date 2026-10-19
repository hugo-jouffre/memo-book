import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { normalizeAccessCode } from "../lib/accessCode.js";

/**
 * **Le lien d'invitation d'un co-voyageur** (Hugo, 18/10/2026) :
 * `https://<l'API>/j/<code>`.
 *
 * - **L'app est installée** : iOS ouvre MemoBook sans passer par ici — c'est
 *   un lien universel, déclaré par `apple-app-site-association` (plus bas) et
 *   par l'*Associated Domain* de `ios/project.yml`. L'app rejoint le voyage et
 *   ouvre son écran d'accueil (`InviteLink`, `RootView.onOpenURL`).
 * - **Elle ne l'est pas** : cette page s'ouvre, et envoie un iPhone ou un iPad
 *   sur la fiche App Store de MemoBook. Le message d'invitation porte aussi le
 *   code en clair : c'est lui qu'on tape dans « Rejoins une aventure » après
 *   l'installation.
 *
 * La page ne lit pas la base : elle ne dit pas si le code existe — une page
 * publique qui répondrait différemment selon le code aiderait qui en essaie.
 */

/** L'équipe Apple et l'app — `ios/project.yml`. */
const APP_ID = "HP2A94889S.com.memobook.app";

/** Le chemin des invitations, le seul que l'app revendique sur ce domaine. */
export const INVITE_PATH = "/j";

const COLORS = {
  background: "#FCF2E9",
  paper: "#FFFCF8",
  ink: "#2D231A",
  inkMuted: "#8A8078",
  action: "#28654B",
  onAction: "#FFFCF8",
};

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/** La fiche App Store de MemoBook ; une recherche tant que l'identifiant n'est pas posé. */
export function appStoreUrl(appleId: number | undefined): string {
  return appleId ? `https://apps.apple.com/app/id${appleId}` : "https://apps.apple.com/fr/search?term=MemoBook";
}

/** Ce que l'app ouvre quand le lien universel n'a pas joué : `memobook://join?code=…`. */
export function appInviteUrl(code: string): string {
  return `memobook://join?code=${encodeURIComponent(code)}`;
}

/**
 * Le fichier qu'Apple vient lire pour savoir que l'app peut ouvrir les liens
 * `/j/…` de ce domaine. Servi en JSON, sans redirection, sans extension.
 */
export function appSiteAssociation() {
  return {
    applinks: {
      details: [{ appIDs: [APP_ID], components: [{ "/": `${INVITE_PATH}/*`, comment: "Invitation d'un co-voyageur" }] }],
    },
  };
}

export function renderInvitePage(code: string, storeUrl: string): string {
  const appUrl = escapeHtml(appInviteUrl(code));
  const store = escapeHtml(storeUrl);
  const shown = escapeHtml(code);
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Rejoins le voyage sur MemoBook</title>
<style>
  body { margin:0; background:${COLORS.background}; color:${COLORS.ink};
    font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif; }
  main { max-width:480px; margin:32px auto; padding:0 16px; }
  .card { background:${COLORS.paper}; border-radius:20px; overflow:hidden; }
  .brand { background:${COLORS.action}; color:${COLORS.onAction}; text-align:center; padding:40px 24px;
    font-family:Georgia,'Times New Roman',serif; font-size:36px; line-height:36px; font-weight:700; letter-spacing:2px; }
  .body { padding:32px 24px; }
  h1 { margin:0 0 16px; font-size:22px; line-height:28px; }
  p { margin:0 0 16px; font-size:15px; line-height:22px; }
  .code { font-size:28px; letter-spacing:6px; font-weight:700; text-align:center; margin:8px 0 24px; }
  .muted { color:${COLORS.inkMuted}; font-size:13px; line-height:18px; }
  .button { display:block; text-align:center; background:${COLORS.action}; color:${COLORS.onAction};
    text-decoration:none; font-size:15px; font-weight:600; line-height:20px; padding:14px 28px;
    border-radius:12px; margin:24px 0 12px; }
  .link { display:block; text-align:center; color:${COLORS.action}; font-size:15px; font-weight:600; margin:0 0 16px; }
</style>
<script>
  // Sur iPhone et iPad, l'App Store tout de suite : si l'app était là, iOS
  // l'aurait ouverte sans afficher cette page.
  if (/iPhone|iPad|iPod/.test(navigator.userAgent)) {
    window.addEventListener("load", function () { window.location.href = ${JSON.stringify(storeUrl)}; });
  }
</script>
</head>
<body>
<main><div class="card">
<div class="brand">MEMO<br>BOOK</div>
<div class="body">
<h1>On t’attend pour raconter ce voyage</h1>
<p>Installe MemoBook, puis entre ce code dans « Rejoins une aventure » :</p>
<p class="code">${shown}</p>
<a class="button" href="${store}">Télécharger MemoBook</a>
<a class="link" href="${appUrl}">J’ai déjà l’app</a>
<p class="muted">MemoBook est une app pour iPhone.</p>
</div>
</div></main>
</body>
</html>`;
}

export function registerInvitePageRoutes(app: FastifyInstance, context: AppContext): void {
  const association = async (_request: unknown, reply: import("fastify").FastifyReply) =>
    reply.header("Cache-Control", "public, max-age=3600").type("application/json").send(appSiteAssociation());
  app.get("/.well-known/apple-app-site-association", association);
  app.get("/apple-app-site-association", association);

  app.get<{ Params: { code: string } }>(`${INVITE_PATH}/:code`, { logLevel: "warn" }, async (request, reply) => {
    const code = normalizeAccessCode(request.params.code ?? "");
    reply.header("Cache-Control", "no-store").type("text/html; charset=utf-8");
    return reply.send(renderInvitePage(code, appStoreUrl(context.env.APP_STORE_APP_APPLE_ID)));
  });
}
