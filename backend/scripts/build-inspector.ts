#!/usr/bin/env tsx
/**
 * Fabrique l'inspecteur de mise en page : une page HTML autonome qui affiche
 * le carnet rendu et nomme chaque élément au survol.
 *
 * Le but est de rendre les demandes de retouche précises. Plutôt que « le
 * bloc avec la pince est trop haut », l'inspecteur donne le nom du composant,
 * son sélecteur, les champs JSON qui l'alimentent et les variables CSS en jeu.
 *
 *   npm run inspector          régénère .render-out/inspecteur.html
 *
 * Tout est inliné (polices en base64, images en data URI) : la page doit
 * fonctionner sans réseau, y compris publiée en artefact.
 */
import { existsSync, readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { TEMPLATE_DIR, loadTemplateCss } from "../src/lib/templates.js";
import { renderTemplateToHtml } from "../src/services/bookPdf.js";

const OFFLINE_DIR = resolve(import.meta.dirname, "../test/fixtures/offline");
const OUTPUT = resolve(import.meta.dirname, "../.render-out/inspecteur.html");

// ---------------------------------------------------------------------------
// Dictionnaire d'annotation
// ---------------------------------------------------------------------------

interface Part {
  /** Nom lisible, celui qu'on emploie en parlant du carnet. */
  name: string;
  /** Ce que l'élément fait, en une phrase. */
  role: string;
  /** Champs du payload qui l'alimentent. */
  fields?: string[];
  /** Variables CSS qui le pilotent. */
  vars?: string[];
  /** Famille, pour le regroupement et la couleur de la pastille. */
  kind: "page" | "structure" | "composant" | "decor";
}

/**
 * Indexé par classe CSS. L'annotation vit ici plutôt que dans `index.html` :
 * le gabarit part chez APITemplate tel quel, il n'a pas à porter les
 * métadonnées d'un outil de travail.
 */
const PARTS: Record<string, Part> = {
  // --- Pages ---------------------------------------------------------------
  "page--cover": { kind: "page", name: "Couverture", role: "Photo pleine page, titre et signature. Ni teinte ni grain : la photo occupe tout.", fields: ["book_title", "book_subtitle", "authors", "date_range", "cover_photo"] },
  "page--colophon": { kind: "page", name: "Page de garde", role: "La page « Tout commence… par une feuille blanche », avec les mentions d'édition.", fields: ["brand_name", "year", "authors"] },
  "page--intro": { kind: "page", name: "Page d'introduction", role: "Récit d'ouverture manuscrit, précédé de deux photos scotchées. N'apparaît que si intro_text est fourni.", fields: ["intro_title", "intro_text", "intro_photos"] },
  "page--day": { kind: "page", name: "Page de journée", role: "Une entrée de days[] = une page. Le layout est choisi par les drapeaux layout_*.", fields: ["days[]"] },
  "page--back": { kind: "page", name: "Quatrième de couverture", role: "Photo pleine page et mot de fin.", fields: ["back_cover"] },

  // --- Structure -----------------------------------------------------------
  "page__content": { kind: "structure", name: "Zone de contenu", role: "Colonne flex à 30 pt de marge. Tout ce qui doit rester dans les marges d'impression vit ici.", vars: ["--mb-margin"] },
  "page__decor": { kind: "structure", name: "Calque décor", role: "Sous le contenu. Ce qui déborde volontairement des marges : tracés, stickers.", },
  "mb-split": { kind: "structure", name: "Bloc scindé", role: "Carte info d'un côté, récit de l'autre. Ne se comprime jamais : c'est la bande de photos qui cède.", },
  "mb-split__aside": { kind: "structure", name: "Colonne latérale", role: "Reçoit la carte info. Largeur fixe de 173 pt.", },
  "mb-split__main": { kind: "structure", name: "Colonne de récit", role: "Le texte manuscrit, en colonne étroite." },
  "mb-gallery": { kind: "structure", name: "Bande de photos", role: "2 ou 3 photos alignées, calées en bas de page. Se comprime si le récit est long.", fields: ["day.photos"] },
  "mb-day__floats": { kind: "structure", name: "Zone flottante", role: "Bas de la page de journée : carte info à gauche, photo à droite. Absorbe la hauteur restante." },
  "mb-intro__photos": { kind: "structure", name: "Photos d'introduction", role: "Deux photos inclinées, positionnées en absolu.", fields: ["intro_photos"] },

  // --- Composants ----------------------------------------------------------
  "mb-header": { kind: "composant", name: "Bandeau de journée", role: "Ruban « jour NN », encart lieu, encart date. Ne s'affiche que si day_intro est présent.", fields: ["day.day_intro"] },
  "mb-ribbon": { kind: "composant", name: "Ruban de journée", role: "Fanion à encoche partant du bord haut de la page.", fields: ["day.day_intro.day_number"] },
  "mb-ribbon__number": { kind: "composant", name: "Numéro de jour", role: "Playfair Display Black 27,6 pt, légèrement pivoté.", fields: ["day.day_intro.day_number"] },
  "mb-ribbon__label": { kind: "composant", name: "Mot « jour »", role: "Playfair Display Black 10,4 pt au-dessus du numéro." },
  "mb-field": { kind: "composant", name: "Encart lieu / date", role: "Cadre tracé à la main : deux contours désalignés, pas une bordure nette.", fields: ["day.day_intro.location", "day.day_intro.date"] },
  "mb-field__label": { kind: "composant", name: "Pastille d'encart", role: "Le petit « lieu » ou « date » posé sur le bord haut du cadre.", vars: ["--mb-label"] },
  "mb-field__value": { kind: "composant", name: "Valeur d'encart", role: "Le lieu ou la date. Trop long, il élargit le cadre au détriment de l'autre.", fields: ["day.day_intro.location", "day.day_intro.date"] },
  "mb-weather": { kind: "composant", name: "Rangée météo", role: "Cinq icônes ; celle du jour passe en carotte, les autres restent à 30 % d'opacité.", fields: ["day.day_intro.weather_key"] },
  "mb-weather__icon": { kind: "composant", name: "Icône météo", role: "SVG au trait, 20 pt. Valeurs possibles : sun, sun-wind, cloud, rain, snow.", fields: ["day.day_intro.weather_key"], vars: ["--mb-carrot"] },
  "mb-tag": { kind: "composant", name: "Étiquette de section", role: "Pastille manuscrite (« Top départ »). Trois mots maximum, sinon elle déborde de sa forme.", fields: ["day.tag"] },
  "mb-note": { kind: "composant", name: "Bloc de texte manuscrit", role: "Encre bleue sur lignes réglées. Les lignes sont générées en dégradé répété, calées sur l'interlignage.", fields: ["day.body_html", "intro_text"], vars: ["--mb-ink", "--mb-rule", "--mb-line", "--mb-font-hand"] },
  "mb-note__title": { kind: "composant", name: "Titre manuscrit", role: "16 pt. Devrait être en Hansley — police propriétaire encore absente, repli sur Gloria Hallelujah.", fields: ["day.title", "intro_title"], vars: ["--mb-font-title"] },
  "mb-card": { kind: "composant", name: "Carte info", role: "Carte blanche pivotée de 6,5°, liseré pointillé, ombre bleutée. Seul le premier fun fact est affiché.", fields: ["day.fun_facts[0]", "day.fun_facts_title"], vars: ["--mb-card-bg", "--mb-card-shadow"] },
  "mb-card__title": { kind: "composant", name: "Bandeau de carte", role: "Fond menthe, contour plein puis liseré pointillé interne, pivoté de −1°.", fields: ["day.fun_facts_title"], vars: ["--mb-mint"] },
  "mb-card__body": { kind: "composant", name: "Texte de carte", role: "Playfair Display 12 pt. 140 caractères maximum, refusés au-delà par le validateur.", fields: ["day.fun_facts[0]"] },
  "mb-card__clip": { kind: "composant", name: "Pince", role: "Pince métallique posée sur le bord haut de la carte. SVG dessiné, pas une image." },
  "mb-photo": { kind: "composant", name: "Photo scotchée", role: "Bord blanc, rotation légère, ombre portée. Recadrage en object-fit: cover.", fields: ["day.photos[]"], vars: ["--mb-photo-shadow"] },
  "mb-hero": { kind: "composant", name: "Photo héro", role: "Grande photo en tête de page, layout hero_top.", fields: ["day.photos[0]"] },

  // --- Couverture et dos ---------------------------------------------------
  "mb-cover__photo": { kind: "composant", name: "Photo de couverture", role: "Pleine page, sous le titre.", fields: ["cover_photo"] },
  "mb-cover__title": { kind: "composant", name: "Titre du carnet", role: "Playfair Display Black 64 pt. Rétrécit si le titre est long, au lieu de déborder.", fields: ["book_title"] },
  "mb-cover__subtitle": { kind: "composant", name: "Sous-titre", role: "Bandeau blanc incliné sous le titre.", fields: ["book_subtitle"] },
  "mb-cover__byline": { kind: "composant", name: "Signature", role: "Auteurs et période, en bas de couverture.", fields: ["authors", "date_range"] },
  "mb-colophon__credits": { kind: "composant", name: "Mentions d'édition", role: "Marque, année, auteurs.", fields: ["brand_name", "year", "authors"] },
  "mb-back__text": { kind: "composant", name: "Mot de fin", role: "Texte de clôture sur la photo de dos.", fields: ["back_cover.closing_text"] },
  "mb-back__footer": { kind: "composant", name: "Pied de dos", role: "Sous-texte et appel à l'action.", fields: ["back_cover.closing_subtext", "back_cover.cta"] },
  "mb-back__photo": { kind: "composant", name: "Photo de dos", role: "Pleine page.", fields: ["back_cover.image"] },

  // --- Décor ---------------------------------------------------------------
  "mb-path": { kind: "decor", name: "Tracé du voyage", role: "Pointillé orange qui serpente d'un bord à l'autre. Déborde volontairement des marges." },
};

// ---------------------------------------------------------------------------
// Assemblage du document
// ---------------------------------------------------------------------------

const MIME: Record<string, string> = { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png" };

/** Remplace chaque URL distante par son équivalent local en data URI. */
function inlineImages(html: string): string {
  const manifestPath = resolve(OFFLINE_DIR, "manifest.json");
  if (!existsSync(manifestPath)) return html;
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Record<string, string>;

  let out = html;
  for (const [url, file] of Object.entries(manifest)) {
    const path = resolve(OFFLINE_DIR, file);
    if (!existsSync(path)) continue;
    const ext = file.split(".").pop() ?? "png";
    const dataUri = `data:${MIME[ext] ?? "image/png"};base64,${readFileSync(path).toString("base64")}`;
    out = out.split(url).join(dataUri);
  }
  return out;
}

interface PageMeta {
  index: number;
  label: string;
  detail: string;
  layout: string;
}

/** Les valeurs du payload sont typées `unknown` : on n'affiche que les chaînes. */
function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

/** Décrit chaque page pour la navigation latérale. */
function describePages(payload: Record<string, unknown>): PageMeta[] {
  const pages: PageMeta[] = [];
  const push = (label: string, detail: string, layout: string): void => {
    pages.push({ index: pages.length, label, detail, layout });
  };

  push("Couverture", text(payload["book_title"]), "cover");
  push("Page de garde", "Mentions d'édition", "colophon");
  if (payload["intro_text"]) push("Introduction", text(payload["intro_title"], "Intro"), "intro");

  for (const day of (payload["days"] as Record<string, unknown>[] | undefined) ?? []) {
    const intro = day["day_intro"] as Record<string, unknown> | undefined;
    const layout = day["layout_hero_top"]
      ? "hero_top"
      : day["layout_split_left"]
        ? "split_left"
        : day["layout_collage"]
          ? "collage"
          : "story_opener";
    push(`Jour ${text(intro?.["day_number"], "—")}`, text(day["title"]), layout);
  }

  if (payload["back_cover"]) push("Quatrième", "Mot de fin", "back");
  return pages;
}

/**
 * Transporte le document du carnet jusqu'au navigateur.
 *
 * Le contenu d'un <script> n'est PAS décodé par le parseur HTML : y déposer du
 * HTML échappé donnerait un mur de texte au lieu d'une page. On passe donc par
 * du JSON, en échappant `<` pour qu'aucun `</script>` interne ne referme la
 * balise prématurément.
 */
const asJsonPayload = (value: string): string =>
  JSON.stringify(value).replace(/</g, "\\u003c");

async function main(): Promise<void> {
  const payload = JSON.parse(
    readFileSync(resolve(TEMPLATE_DIR, "samples/showcase.json"), "utf8"),
  ) as Record<string, unknown>;

  // Rendu unique : le profil imprimeur est obtenu en redéfinissant deux
  // variables CSS sur la scène, exactement comme le fait `body.profile-print`.
  const carnet = inlineImages(renderTemplateToHtml({ payload, profile: "preview" }));
  const body = carnet.slice(carnet.indexOf("<body"), carnet.lastIndexOf("</body>"));
  const inner = body.slice(body.indexOf(">") + 1);

  const document = `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
${loadTemplateCss()}
<style>
  html, body { background: transparent; }
  body { margin: 0; padding: 0; }
  /* Profil imprimeur : mêmes deux variables que body.profile-print. */
  body.is-print { --mb-paper-tint: transparent; --mb-grain-opacity: 0; }
  .page { margin: 0 auto 28px; box-shadow: 0 10px 30px rgba(12, 16, 24, .22); }
  .page:last-child { margin-bottom: 0; }
  #mb-outline { position: absolute; z-index: 9999; pointer-events: none;
    border: 1.5px solid #f86015; background: rgba(248, 96, 21, .08);
    border-radius: 2px; display: none; }
  #mb-outline.is-pinned { border-style: dashed; background: rgba(248, 96, 21, .14); }
</style></head><body>${inner}<div id="mb-outline"></div></body></html>`;

  const pages = describePages(payload);
  const template = readFileSync(resolve(import.meta.dirname, "inspector-shell.html"), "utf8");

  const html = template
    .replace("__PARTS__", JSON.stringify(PARTS))
    .replace("__PAGES__", JSON.stringify(pages))
    .replace("__DOCUMENT__", asJsonPayload(document));

  await mkdir(resolve(import.meta.dirname, "../.render-out"), { recursive: true });
  await writeFile(OUTPUT, html);
  console.log(`✓ ${OUTPUT} — ${(Buffer.byteLength(html) / 1024).toFixed(0)} ko, ${pages.length} pages`);
}

await main().catch((error: unknown) => {
  console.error(`✗ ${(error as Error).message}`);
  process.exit(1);
});
