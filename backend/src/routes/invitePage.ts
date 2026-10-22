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
 * - **Sur Android**, c'est un App Link : `/.well-known/assetlinks.json` (plus
 *   bas) dit à Android que `com.memobook.app` ouvre ces liens, et l'intent
 *   filter de `android/app/src/main/AndroidManifest.xml` les revendique.
 * - **Elle ne l'est pas** : cette page s'ouvre, et envoie un iPhone ou un iPad
 *   sur la fiche App Store de MemoBook — un téléphone Android sur la fiche du
 *   Play Store, quand l'app y est publiée (`ANDROID_PLAY_STORE_LISTED`). Le
 *   message d'invitation porte aussi le code en clair : c'est lui qu'on tape
 *   dans « Rejoins une aventure » après l'installation.
 *
 * La page ne lit pas la base : elle ne dit pas si le code existe — une page
 * publique qui répondrait différemment selon le code aiderait qui en essaie.
 */

/** L'équipe Apple et l'app — `ios/project.yml`. */
const APP_ID = "HP2A94889S.com.memobook.app";

/** L'app Android — `applicationId` de `android/app/build.gradle.kts`. */
export const ANDROID_PACKAGE = "com.memobook.app";

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

/** La fiche Play Store de MemoBook. */
export function playStoreUrl(): string {
  return `https://play.google.com/store/apps/details?id=${ANDROID_PACKAGE}`;
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

/**
 * Le fichier qu'Android vient lire pour savoir que `com.memobook.app` peut
 * ouvrir les liens de ce domaine sans demander — les invitations et la page du
 * mot de passe. Un certificat par empreinte (`ANDROID_APP_CERT_SHA256`) ; sans
 * empreinte, rien n'est déclaré : une déclaration sans certificat ne vaut rien.
 */
export function androidAssetLinks(fingerprints: string[]) {
  if (fingerprints.length === 0) return [];
  return [
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: { namespace: "android_app", package_name: ANDROID_PACKAGE, sha256_cert_fingerprints: fingerprints },
    },
  ];
}

/** Où envoyer quelqu'un qui n'a pas l'app : la fiche du store de son téléphone. */
export interface InviteStores {
  appStore: string;
  /** `null` tant que l'app Android n'est pas publiée. */
  playStore: string | null;
}

export function renderInvitePage(code: string, stores: InviteStores): string {
  const appUrl = escapeHtml(appInviteUrl(code));
  const store = escapeHtml(stores.appStore);
  const shown = escapeHtml(code);
  const platforms = stores.playStore ? "MemoBook est une app pour iPhone et Android." : "MemoBook est une app pour iPhone.";
  // Sur Android, le lien `memobook://` passe par un `intent://` : Chrome n'ouvre
  // un schéma privé qu'ainsi, et il propose le Play Store si l'app manque.
  const androidStore = stores.playStore ? JSON.stringify(stores.playStore) : "null";
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
  // l'aurait ouverte sans afficher cette page. Sur Android, le Play Store, une
  // fois l'app publiée — un App Link vérifié l'aurait ouverte, lui aussi.
  if (/iPhone|iPad|iPod/.test(navigator.userAgent)) {
    window.addEventListener("load", function () { window.location.href = ${JSON.stringify(stores.appStore)}; });
  } else if (/Android/.test(navigator.userAgent)) {
    var playStore = ${androidStore};
    window.addEventListener("load", function () {
      var download = document.getElementById("download");
      if (playStore) { download.href = playStore; window.location.href = playStore; }
      document.getElementById("open").href = ${JSON.stringify(androidIntentUrl(`join?code=${encodeURIComponent(code)}`))};
    });
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
<a class="button" id="download" href="${store}">Télécharger MemoBook</a>
<a class="link" id="open" href="${appUrl}">J’ai déjà l’app</a>
<p class="muted">${platforms}</p>
</div>
</div></main>
</body>
</html>`;
}

/**
 * Un lien `memobook://<chemin>` sous la forme qu'Android ouvre depuis Chrome :
 * `intent://<chemin>#Intent;scheme=memobook;package=com.memobook.app;end`.
 */
export function androidIntentUrl(path: string): string {
  return `intent://${path}#Intent;scheme=memobook;package=${ANDROID_PACKAGE};end`;
}

export function registerInvitePageRoutes(app: FastifyInstance, context: AppContext): void {
  const association = async (_request: unknown, reply: import("fastify").FastifyReply) =>
    reply.header("Cache-Control", "public, max-age=3600").type("application/json").send(appSiteAssociation());
  app.get("/.well-known/apple-app-site-association", association);
  app.get("/apple-app-site-association", association);
  app.get("/.well-known/assetlinks.json", async (_request, reply) =>
    reply
      .header("Cache-Control", "public, max-age=3600")
      .type("application/json")
      .send(androidAssetLinks(context.env.ANDROID_APP_CERT_SHA256)),
  );

  app.get<{ Params: { code: string } }>(`${INVITE_PATH}/:code`, { logLevel: "warn" }, async (request, reply) => {
    const code = normalizeAccessCode(request.params.code ?? "");
    reply.header("Cache-Control", "no-store").type("text/html; charset=utf-8");
    return reply.send(
      renderInvitePage(code, {
        appStore: appStoreUrl(context.env.APP_STORE_APP_APPLE_ID),
        playStore: context.env.ANDROID_PLAY_STORE_LISTED ? playStoreUrl() : null,
      }),
    );
  });
}
