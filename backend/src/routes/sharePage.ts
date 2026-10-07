import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { frenchDate } from "../lib/frenchFormat.js";
import { shareUrlOf } from "../services/shareLink.js";

/**
 * **La page d'un carnet partagé** — `GET /c/:jeton` (T229, Hugo 06/10/2026).
 *
 * Le lien de la feuille « Partager » et de « Recevoir sur WhatsApp » existait
 * (`POST /v1/memos/:id/share-link`), la page derrière, non : il menait sur
 * memo-book.com, qui répondait 404. Hugo voulait qu'on la configure ou qu'on
 * la retire pour la v1 ; elle existe, simple : le titre, les dates, la photo de
 * couverture, les étapes et les premières phrases du récit. Rien d'autre — ni
 * les textes entiers, ni les photos des souvenirs (le seau est privé), ni qui
 * a voyagé.
 *
 * **Les balises Open Graph font la vignette** : WhatsApp, iMessage, Messenger
 * lisent `og:title`, `og:description` et `og:image` pour dessiner l'aperçu du
 * lien dans la conversation. C'est souvent tout ce que le destinataire verra.
 *
 * Publique par nature : le destinataire n'a pas de compte. Le jeton (96 bits,
 * `newShareSlug`) est la seule clé, et il ne s'écrit pas dans les journaux
 * (`logLevel: "warn"`), comme le lien d'export des données.
 */

const COLORS = {
  background: "#FCF2E9",
  paper: "#FFFCF8",
  ink: "#2D231A",
  inkMuted: "#8A8078",
  action: "#28654B",
  onAction: "#FFFCF8",
};

/** Le jeton tel que `newShareSlug` le fabrique : base64url, seize caractères. */
const SLUG_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/** Seule une adresse `https` publique peut servir d'image à une vignette. */
function publicImage(url: string | null | undefined): string | null {
  return url && /^https:\/\//.test(url) ? url : null;
}

/** « du 5 au 12 janvier 2026 », « depuis le 5 janvier 2026 », ou rien. */
export function tripDates(startDate: Date | null, endDate: Date | null): string | null {
  if (!startDate) return null;
  if (!endDate) return `depuis le ${frenchDate(startDate)}`;
  const start = frenchDate(startDate);
  const end = frenchDate(endDate);
  if (start === end) return `le ${start}`;
  // « du 5 au 12 janvier 2026 » plutôt que « du 5 janvier 2026 au 12 janvier
  // 2026 » : on garde du début ce qui le distingue de la fin.
  const [startDay, startMonth, startYear] = start.split(" ");
  const [, endMonth, endYear] = end.split(" ");
  if (startYear === endYear && startMonth === endMonth) return `du ${startDay} au ${end}`;
  if (startYear === endYear) return `du ${startDay} ${startMonth} au ${end}`;
  return `du ${start} au ${end}`;
}

/** Les premières phrases du récit, coupées sur un mot. */
function excerptOf(texts: (string | null)[], max = 220): string | null {
  const text = texts
    .filter((value): value is string => Boolean(value?.trim()))
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
  if (!text) return null;
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const lastSpace = cut.lastIndexOf(" ");
  return `${(lastSpace > max / 2 ? cut.slice(0, lastSpace) : cut).trimEnd()}…`;
}

interface SharedTrip {
  title: string;
  url: string;
  dates: string | null;
  imageUrl: string | null;
  steps: string[];
  excerpt: string | null;
}

function page(head: string, body: string): string {
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
${head}
<style>
  body { margin:0; background:${COLORS.background}; color:${COLORS.ink};
    font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif; }
  main { max-width:520px; margin:32px auto; padding:0 16px; }
  .card { background:${COLORS.paper}; border-radius:20px; overflow:hidden; }
  .brand { background:${COLORS.action}; color:${COLORS.onAction}; text-align:center; padding:20px 24px;
    font-family:Georgia,'Times New Roman',serif; font-size:20px; font-weight:700; letter-spacing:2px; }
  .cover { display:block; width:100%; max-height:360px; object-fit:cover; }
  .body { padding:28px 24px 32px; }
  h1 { margin:0 0 8px; font-family:Georgia,'Times New Roman',serif; font-size:28px; line-height:34px; }
  .dates { margin:0 0 20px; color:${COLORS.inkMuted}; font-size:15px; }
  blockquote { margin:0 0 24px; padding:0 0 0 16px; border-left:3px solid ${COLORS.action};
    font-family:Georgia,'Times New Roman',serif; font-size:17px; line-height:26px; font-style:italic; }
  h2 { margin:0 0 8px; font-size:15px; text-transform:uppercase; letter-spacing:1px; color:${COLORS.inkMuted}; }
  ol { margin:0 0 24px; padding-left:22px; font-size:16px; line-height:26px; }
  p { margin:0 0 12px; font-size:15px; line-height:22px; }
  .muted { color:${COLORS.inkMuted}; font-size:13px; line-height:18px; }
  a { color:${COLORS.action}; }
</style>
</head>
<body>
<main><div class="card">
<div class="brand">MEMO BOOK</div>
${body}
</div></main>
</body>
</html>`;
}

export function renderSharedTripPage(trip: SharedTrip): string {
  const description =
    trip.excerpt ?? (trip.dates ? `Un carnet de voyage MemoBook, ${trip.dates}.` : "Un carnet de voyage MemoBook.");

  const head = [
    `<title>${escapeHtml(trip.title)} — MemoBook</title>`,
    `<meta name="description" content="${escapeHtml(description)}">`,
    `<meta property="og:type" content="article">`,
    `<meta property="og:site_name" content="MemoBook">`,
    `<meta property="og:locale" content="fr_FR">`,
    `<meta property="og:title" content="${escapeHtml(trip.title)}">`,
    `<meta property="og:description" content="${escapeHtml(description)}">`,
    `<meta property="og:url" content="${escapeHtml(trip.url)}">`,
    ...(trip.imageUrl ? [`<meta property="og:image" content="${escapeHtml(trip.imageUrl)}">`] : []),
    `<meta name="twitter:card" content="${trip.imageUrl ? "summary_large_image" : "summary"}">`,
  ].join("\n");

  const body = [
    trip.imageUrl ? `<img class="cover" src="${escapeHtml(trip.imageUrl)}" alt="">` : "",
    `<div class="body">`,
    `<h1>${escapeHtml(trip.title)}</h1>`,
    trip.dates ? `<p class="dates">${escapeHtml(trip.dates)}</p>` : "",
    trip.excerpt ? `<blockquote>${escapeHtml(trip.excerpt)}</blockquote>` : "",
    trip.steps.length > 0
      ? `<h2>Les étapes</h2>\n<ol>${trip.steps.map((step) => `<li>${escapeHtml(step)}</li>`).join("")}</ol>`
      : "",
    `<p>Ce carnet s’écrit avec MemoBook : on raconte son voyage à voix haute, il devient un livre.</p>`,
    `<p class="muted">Ce lien ne montre qu’un aperçu. Le carnet entier reste entre ceux qui l’écrivent.</p>`,
    `</div>`,
  ]
    .filter(Boolean)
    .join("\n");

  return page(head, body);
}

export function renderUnknownSharePage(): string {
  return page(
    `<title>Carnet introuvable — MemoBook</title>`,
    `<div class="body">
<h1>Ce carnet n’est plus partagé</h1>
<p>Le lien est peut-être incomplet, ou le carnet a été supprimé. Demande à celui qui te l’a envoyé de le partager à nouveau.</p>
</div>`,
  );
}

export function registerSharePageRoutes(app: FastifyInstance, context: AppContext): void {
  app.get<{ Params: { slug: string } }>("/c/:slug", { logLevel: "warn" }, async (request, reply) => {
    const { slug } = request.params;
    const send = (status: number, html: string) =>
      reply
        .code(status)
        .type("text/html; charset=utf-8")
        // Quelques minutes : la vignette suit le carnet sans que chaque
        // aperçu de lien ne relise la base.
        .header("Cache-Control", status === 200 ? "public, max-age=300" : "no-store")
        .send(html);

    if (!SLUG_PATTERN.test(slug)) return send(404, renderUnknownSharePage());

    const memo = await context.prisma.memo.findUnique({
      where: { shareSlug: slug },
      select: {
        title: true,
        bookTitle: true,
        startDate: true,
        endDate: true,
        coverPhotoUrl: true,
        steps: { orderBy: { number: "asc" }, select: { placeName: true, destinationName: true, photoUrl: true } },
        entries: {
          where: { kind: { not: "photo" } },
          orderBy: [{ capturedAt: "asc" }, { createdAt: "asc" }],
          take: 3,
          select: { editedText: true, redactedText: true },
        },
      },
    });
    if (!memo) return send(404, renderUnknownSharePage());

    return send(
      200,
      renderSharedTripPage({
        title: memo.bookTitle?.trim() || memo.title,
        url: shareUrlOf(context.env, slug),
        dates: tripDates(memo.startDate, memo.endDate),
        imageUrl:
          publicImage(memo.coverPhotoUrl) ?? publicImage(memo.steps.find((step) => step.photoUrl)?.photoUrl),
        steps: memo.steps.flatMap((step) => {
          const name = step.placeName ?? step.destinationName;
          return name ? [name] : [];
        }),
        // Le texte relu, jamais la transcription brute : hésitations et « euh »
        // n'ont rien à faire dans la vignette d'un lien.
        excerpt: excerptOf(memo.entries.map((entry) => entry.editedText ?? entry.redactedText)),
      }),
    );
  });
}
