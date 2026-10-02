import type { FastifyInstance, FastifyReply } from "fastify";
import type { AppContext } from "../context.js";
import { frenchCount, frenchDate, frenchSize } from "../lib/frenchFormat.js";
import {
  DATA_EXPORT_MAX_DOWNLOADS,
  findDataExport,
  recordDataExportDownload,
} from "../services/dataExport.js";
import {
  planDataExport,
  streamArchive,
  type ExportSummary,
} from "../services/dataExportArchive.js";
import { DATA_EXPORT_CONTENTS } from "../services/mailTemplates.js";

/**
 * La page derrière le bouton « Télécharger mes données » de l'e-mail, et
 * l'archive derrière le sien.
 *
 * **Deux adresses, et pas une seule qui télécharge directement.** Les
 * messageries d'entreprise et certains antivirus ouvrent les liens d'un e-mail
 * pour les inspecter avant qu'on clique : un lien qui composait l'archive
 * l'aurait composée pour eux, à chaque fois, et compté comme un
 * téléchargement. La page ne coûte qu'une poignée de requêtes et ne consomme
 * rien ; c'est son bouton qui lance l'archive.
 *
 * Elle sert aussi à **dire où on en est** — ce que l'archive contient, ce
 * qu'elle pèse, jusqu'à quand le lien vaut — et à répondre en mots, et non en
 * JSON, quand le lien ne vaut plus rien.
 *
 * Publiques par nature : on y arrive depuis une boîte mail, sans session. Le
 * secret du lien est la seule clé, et il ne s'écrit pas dans les logs
 * (`logLevel: "warn"`), comme celui du mot de passe oublié.
 */

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

function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<title>${escapeHtml(title)}</title>
<style>
  body { margin:0; background:${COLORS.background}; color:${COLORS.ink};
    font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif; }
  main { max-width:480px; margin:32px auto; padding:0 16px; }
  .card { background:${COLORS.paper}; border-radius:20px; overflow:hidden; }
  .brand { background:${COLORS.action}; color:${COLORS.onAction}; text-align:center; padding:40px 24px;
    font-family:Georgia,'Times New Roman',serif; font-size:36px; line-height:36px; font-weight:700; letter-spacing:2px; }
  .body { padding:32px 24px; }
  h1 { margin:0 0 16px; font-size:22px; line-height:28px; }
  h2 { margin:24px 0 8px; font-size:16px; line-height:22px; }
  p { margin:0 0 16px; font-size:15px; line-height:22px; }
  .facts { margin:0 0 4px; font-size:15px; line-height:22px; font-weight:600; }
  .muted { color:${COLORS.inkMuted}; font-size:13px; line-height:18px; }
  .button { display:block; text-align:center; background:${COLORS.action}; color:${COLORS.onAction};
    text-decoration:none; font-size:15px; font-weight:600; line-height:20px; padding:14px 28px;
    border-radius:12px; margin:24px 0 12px; }
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

const ASK_AGAIN = "Tu peux redemander un export depuis l’app : Profil ▸ Exporter mes données.";

export function renderIncompleteLinkPage(): string {
  return page(
    "Lien incomplet — MemoBook",
    `<h1>Ce lien est incomplet</h1>
<p>Il lui manque le secret qui ouvre tes données — il a sans doute été coupé en route. Ouvre le lien de l’e-mail tel quel.</p>
<p class="muted">${ASK_AGAIN}</p>`,
  );
}

/** Inconnu, expiré ou remplacé : un seul message, voir `findDataExport`. */
export function renderInvalidLinkPage(): string {
  return page(
    "Lien expiré — MemoBook",
    `<h1>Ce lien n’est plus valable</h1>
<p>Un lien d’export vaut sept jours, et une demande plus récente remplace la précédente : utilise le dernier e-mail reçu.</p>
<p class="muted">${ASK_AGAIN}</p>`,
  );
}

export function renderExhaustedLinkPage(): string {
  return page(
    "Lien épuisé — MemoBook",
    `<h1>Ce lien a déjà beaucoup servi</h1>
<p>Il a permis ${DATA_EXPORT_MAX_DOWNLOADS} téléchargements : par prudence, il s’arrête là. Si ce n’est pas toi, réponds à l’e-mail qui t’a envoyé le lien.</p>
<p class="muted">${ASK_AGAIN}</p>`,
  );
}

export function renderUnavailablePage(): string {
  return page(
    "Archive indisponible — MemoBook",
    `<h1>Ton archive n’a pas pu se préparer</h1>
<p>Ce n’est pas de ton fait : réessaie dans un instant. Si ça continue, réponds à l’e-mail qui t’a envoyé le lien.</p>`,
  );
}

/**
 * « 3 voyages · 412 souvenirs · 230 photos · 45 vocaux · 2 carnets en PDF ».
 * Chaque nombre tient à son nom par une espace insécable : « 45 » en fin de
 * ligne et « vocaux » au début de la suivante ne se lisent plus ensemble.
 */
export function describeSummary(summary: ExportSummary): string {
  return [
    frenchCount(summary.trips, "voyage", "voyages"),
    frenchCount(summary.memories, "souvenir", "souvenirs"),
    frenchCount(summary.photos, "photo", "photos"),
    frenchCount(summary.voiceNotes, "vocal", "vocaux"),
    ...(summary.books > 0 ? [frenchCount(summary.books, "carnet en PDF", "carnets en PDF")] : []),
  ]
    .map((count) => count.replace(" ", " "))
    .join(" · ");
}

export function renderDownloadPage(input: {
  token: string;
  email: string;
  requestedAt: Date;
  expiresAt: Date;
  summary: ExportSummary;
}): string {
  const { summary } = input;
  const archiveUrl = `/data-export/archive?token=${encodeURIComponent(input.token)}`;
  // Les carnets se téléchargent chez le service qui les a composés : leur
  // poids n'est connu qu'une fois là.
  const weight = `Environ ${frenchSize(summary.knownBytes)}${summary.books > 0 ? ", sans compter les carnets" : ""}.`;

  return page(
    "Tes données MemoBook",
    `<h1>Tes données MemoBook</h1>
<p>Demandées le ${escapeHtml(frenchDate(input.requestedAt))} pour ${escapeHtml(input.email)}.</p>
<p class="facts">${escapeHtml(describeSummary(summary))}</p>
<p class="muted">${escapeHtml(weight)}</p>
<a class="button" href="${escapeHtml(archiveUrl)}">Télécharger mes données</a>
<p class="muted">Le lien est valable jusqu’au ${escapeHtml(frenchDate(input.expiresAt, { weekday: true }))}, et sert plusieurs fois.</p>
<h2>Bon à savoir</h2>
<p>L’archive se compose pendant le téléchargement : il démarre tout de suite, mais peut durer quelques minutes. Garde la page ouverte jusqu’au bout ; s’il s’interrompt, relance-le.</p>
<p>Dans l’archive : ${escapeHtml(DATA_EXPORT_CONTENTS)}. Le fichier LISEZ-MOI.txt dit ce qu’il y a où.</p>
<p class="muted">Ce lien ouvre toutes tes données : ne le transfère à personne.</p>`,
  );
}

/** Les en-têtes de toutes les réponses : rien en cache, rien dans un référent. */
function protect(reply: FastifyReply): FastifyReply {
  return reply
    .header("Cache-Control", "no-store")
    .header("Referrer-Policy", "no-referrer")
    .header("X-Robots-Tag", "noindex")
    .header("X-Content-Type-Options", "nosniff");
}

function html(reply: FastifyReply, status: number, body: string): FastifyReply {
  return protect(reply).code(status).type("text/html; charset=utf-8").send(body);
}

/** Télécharge un carnet chez le service qui l'a composé. */
async function fetchBook(url: string, signal: AbortSignal): Promise<Buffer> {
  const response = await fetch(url, { signal });
  if (!response.ok) throw new Error(`Le carnet a répondu ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}

export function registerDataExportPageRoutes(app: FastifyInstance, context: AppContext): void {
  app.get<{ Querystring: { token?: string } }>(
    "/data-export",
    { logLevel: "warn" },
    async (request, reply) => {
      const token = typeof request.query.token === "string" ? request.query.token : "";
      if (token === "") return html(reply, 400, renderIncompleteLinkPage());

      const found = await findDataExport(context.prisma, token);
      if (found.status === "invalid") return html(reply, 410, renderInvalidLinkPage());
      if (found.status === "exhausted") return html(reply, 429, renderExhaustedLinkPage());

      try {
        const plan = await planDataExport(context, found.dataExport.accountId);
        return html(
          reply,
          200,
          renderDownloadPage({
            token,
            email: found.dataExport.email,
            requestedAt: found.dataExport.createdAt,
            expiresAt: found.dataExport.expiresAt,
            summary: plan.summary,
          }),
        );
      } catch (error) {
        request.log.error({ err: error }, "La page d’export des données n’a pas pu se préparer");
        return html(reply, 500, renderUnavailablePage());
      }
    },
  );

  app.get<{ Querystring: { token?: string } }>(
    "/data-export/archive",
    { logLevel: "warn" },
    async (request, reply) => {
      const token = typeof request.query.token === "string" ? request.query.token : "";
      if (token === "") return html(reply, 400, renderIncompleteLinkPage());

      const found = await findDataExport(context.prisma, token);
      if (found.status === "invalid") return html(reply, 410, renderInvalidLinkPage());
      if (found.status === "exhausted") return html(reply, 429, renderExhaustedLinkPage());

      let plan;
      try {
        plan = await planDataExport(context, found.dataExport.accountId);
        await recordDataExportDownload(context.prisma, found.dataExport.id);
      } catch (error) {
        request.log.error({ err: error }, "L’archive d’export n’a pas pu se préparer");
        return html(reply, 500, renderUnavailablePage());
      }

      // Le client part — onglet fermé, réseau coupé : inutile d'aller
      // chercher le reste des médias au stockage.
      const controller = new AbortController();
      reply.raw.on("close", () => {
        if (!reply.raw.writableFinished) controller.abort();
      });

      const archive = streamArchive(
        plan,
        {
          storage: context.storage,
          fetchBook,
          onProblem: (details, message) => request.log.warn(details, message),
        },
        controller.signal,
      );

      return protect(reply)
        .code(200)
        .type("application/zip")
        .header("Content-Disposition", `attachment; filename="${plan.rootName}.zip"`)
        .send(archive);
    },
  );
}
