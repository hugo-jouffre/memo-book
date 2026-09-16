import type { FastifyInstance } from "fastify";

/**
 * La page derrière le bouton « Réinitialiser mon mot de passe » de l'e-mail.
 *
 * Le lien de l'e-mail ne peut pas être `memobook://…` : Gmail, Outlook et la
 * plupart des clients mail n'en font pas un lien cliquable — un schéma qu'ils
 * ne connaissent pas est du texte. Un lien `https://` est cliquable partout ;
 * il mène ici, et c'est **cette page** qui ouvre l'app par son schéma privé
 * (déclaré dans `ios/project.yml`, lu par `PasswordResetLink`).
 *
 * Le jour du lien universel (`apple-app-site-association` servi par ce même
 * domaine, *Associated Domain* dans `project.yml`), iOS ouvrira l'app avant
 * même d'arriver ici ; la page restera le repli pour un appareil sans l'app.
 *
 * La page ne touche pas à la base : elle ne consomme rien, ne dit pas si le
 * secret est encore bon — c'est l'app qui le dira, et une page publique qui
 * répond différemment selon le secret aiderait qui en essaie.
 */

/** Ce que l'app iOS déclare et lit : `memobook://password/reset?token=…`. */
const APP_SCHEME_BASE_URL = "memobook://";

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

export function appPasswordResetUrl(token: string): string {
  return `${APP_SCHEME_BASE_URL}password/reset?token=${encodeURIComponent(token)}`;
}

function page(body: string, head = ""): string {
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Réinitialise ton mot de passe MemoBook</title>
${head}
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
  .muted { color:${COLORS.inkMuted}; font-size:13px; line-height:18px; }
  .button { display:block; text-align:center; background:${COLORS.action}; color:${COLORS.onAction};
    text-decoration:none; font-size:15px; font-weight:600; line-height:20px; padding:14px 28px;
    border-radius:12px; margin:24px 0 16px; }
</style>
</head>
<body>
<main><div class="card">
<div class="brand">MEMO<br>BOOK</div>
<div class="body">
${body}
</div>
</div></main>
</body>
</html>`;
}

export function renderPasswordResetPage(token: string): string {
  const appUrl = escapeHtml(appPasswordResetUrl(token));
  return page(
    `<h1>Réinitialise ton mot de passe</h1>
<p>On ouvre MemoBook pour que tu choisisses ton nouveau mot de passe.</p>
<a class="button" href="${appUrl}">Ouvrir MemoBook</a>
<p class="muted">Si rien ne se passe, appuie sur le bouton. Si l’app ne s’ouvre toujours pas, c’est qu’elle n’est pas installée sur cet appareil : ouvre ce lien depuis l’iPhone où MemoBook est installé.</p>`,
    // L'ouverture automatique : Safari propose « Ouvrir dans MemoBook ? ».
    // Sans JavaScript, le bouton fait la même chose.
    `<script>window.addEventListener("load", function () { window.location.href = ${JSON.stringify(
      appPasswordResetUrl(token),
    )}; });</script>`,
  );
}

function renderMissingTokenPage(): string {
  return page(
    `<h1>Ce lien est incomplet</h1>
<p>Il lui manque le secret qui permet de choisir un nouveau mot de passe — il a sans doute été coupé en route.</p>
<p class="muted">Redemande un e-mail depuis « Mot de passe oublié » dans l’app, et ouvre le lien tel quel.</p>`,
  );
}

export function registerPasswordResetPageRoutes(app: FastifyInstance): void {
  app.get<{ Querystring: { token?: string } }>(
    "/password/reset",
    // Le secret est dans l'URL : cette route ne journalise pas ses requêtes,
    // pour ne pas l'écrire dans les logs — comme `mailer.ts` le garde hors
    // de ceux de production.
    { logLevel: "warn" },
    async (request, reply) => {
      const token = typeof request.query.token === "string" ? request.query.token : "";
      reply.header("Cache-Control", "no-store").type("text/html; charset=utf-8");
      if (token === "") {
        return reply.code(400).send(renderMissingTokenPage());
      }
      return reply.send(renderPasswordResetPage(token));
    },
  );
}
