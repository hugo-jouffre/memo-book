import { existsSync } from "node:fs";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Browser, BrowserContext, Page } from "playwright-core";
import {
  installOfflineRouting,
  renderTemplateToHtml,
  settle,
} from "../src/services/bookPdf.js";
import {
  COLLECTEUR_SOURCE,
  MINIMUM_PHOTOS,
  PHOTO_RATIOS,
  RATIO_TOLERANCE,
  appliquerRatio,
  mesurerRatio,
  photosRequired,
  type Rect,
} from "../src/services/photoRatio.js";
import { validatePayload } from "../src/services/payloadValidator.js";

/**
 * Les quinze cas du ratio texte / photo : trois longueurs de récit croisées
 * avec les cinq paliers, **mesurés sur le rendu réel**.
 *
 * Chaque cas vérifie les trois choses qui comptent, dans cet ordre :
 *
 * 1. **le récit du voyageur est identique, octet pour octet**, avant et après
 *    la mise en page. C'est la règle absolue du chantier : c'est le nombre de
 *    pages et de photos qui s'adapte au texte, jamais l'inverse. La
 *    comparaison se fait sur l'étape entière bout à bout — un paragraphe a le
 *    droit de passer d'une page à la suivante, pas d'être coupé ni réécrit ;
 * 2. **le minimum de photos du palier est respecté** ;
 * 3. **le ratio mesuré est dans la tolérance** (±5 points), ou bien le plan
 *    l'avait annoncé comme un dépassement assumé — le minimum de photos sur un
 *    récit très court, cas documenté dans `docs/ratio-texte-photo.md`.
 *
 * Les légendes par photo du palier 100 % ne sont pas vérifiées ici : elles ne
 * sont pas rendues, « pas de légende sur les pages de photos » (Hugo,
 * 12/10/2026). Voir le rapport.
 *
 * La mesure passe par Chromium, en média `print`, comme la production : le
 * ratio ne se vérifie pas sur une estimation au nombre de caractères, c'est
 * tout le point du chantier.
 */

/** Photo du bundle hors ligne : la mesure ne doit pas dépendre du réseau. */
const PHOTO = "https://cdn.prod.website-files.com/68827087b5bebc3702bf1a54/sample-jour-03a.jpg";

/** De quoi servir le palier le plus gourmand sans jamais manquer de photos. */
const PHOTOS = Array.from({ length: 24 }, () => PHOTO);

/** Un paragraphe de `n` signes, en mots réels — la manuscrite coupe aux espaces. */
function paragraphe(n: number): string {
  const mots =
    "la route serpente entre les rizieres et le vent porte une odeur de terre mouillee nous " +
    "marchons depuis le lever du jour sans croiser personne le chauffeur du jeepney rit quand " +
    "je lui montre le nom du village sur mon carnet il repete deux fois avant de demarrer";
  let texte = "";
  while (texte.length < n) texte += (texte ? " " : "") + mots;
  return `<p>${texte.slice(0, n).trim()}.</p>`;
}

/**
 * Les trois longueurs du barème S / M / L / XL (LAYOUT_KB) : un souvenir court
 * d'une page, une étape moyenne, une étape longue qui déborde sur une seconde
 * page même sans photo.
 */
const RECITS = {
  court: paragraphe(180),
  moyen: paragraphe(280) + paragraphe(260),
  long: paragraphe(340) + paragraphe(340) + paragraphe(340) + paragraphe(330),
} as const;

/** L'étape de départ, telle que l'Agent Mise en page la proposerait. */
function etapeDe(recit: string): Record<string, unknown>[] {
  return [
    {
      title: "Une étape racontée au vocal",
      day_intro: { day_number: "01", location: "Cebu, Philippines", date: "22 fév 2026", stay: "Casa Verde" },
      body_html: recit,
      photos: PHOTOS,
      fun_facts: ["Les Philippines comptent plus de 7000 îles, dont un tiers seulement porte un nom."],
      layout_collage: true,
    },
  ];
}

/** Le récit d'une étape, bout à bout. */
const recitDe = (days: Record<string, unknown>[]): string =>
  days.map((jour) => (typeof jour["body_html"] === "string" ? jour["body_html"] : "")).join("");

/**
 * Le navigateur de la mesure.
 *
 * Playwright ne fournit pas de Chromium pour toutes les plateformes où ce
 * dépôt se développe : à défaut du navigateur groupé, on prend le Chrome du
 * système. `CHROMIUM_PATH` permet d'en désigner un troisième. Sans aucun des
 * trois, la suite le dit et saute la mesure plutôt que d'échouer sur une
 * absence d'outil — mais elle ne saute **jamais** les deux premières
 * vérifications, qui n'ont pas besoin de navigateur.
 */
const CHROMES = [
  process.env["CHROMIUM_PATH"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
].filter((chemin): chemin is string => Boolean(chemin));

let browser: Browser | null = null;
let context: BrowserContext | null = null;

beforeAll(async () => {
  const { chromium } = await import("playwright-core");
  const args = ["--font-render-hinting=none", "--hide-scrollbars"];
  try {
    browser = await chromium.launch({ args });
  } catch {
    const executablePath = CHROMES.find((chemin) => existsSync(chemin));
    if (!executablePath) return;
    browser = await chromium.launch({ args, executablePath });
  }
  context = await browser.newContext({ deviceScaleFactor: 1, locale: "fr-FR" });
  await installOfflineRouting(context);
}, 120_000);

afterAll(async () => {
  await browser?.close();
});

interface Mesure {
  ratio: number;
  photos: number;
  pages: number;
}

/** Le rendu d'un payload, mesuré page par page. */
async function mesurer(payload: Record<string, unknown>): Promise<Mesure | null> {
  if (!context) return null;
  let page: Page | null = null;
  try {
    page = await context.newPage();
    await page.emulateMedia({ media: "print" });
    await page.setContent(renderTemplateToHtml({ payload, profile: "print" }), { waitUntil: "load" });
    await settle(page);

    const releve = await page.evaluate(
      ([source]) => {
        const collecter = eval(source as string) as (
          pages: Element[],
        ) => { photos: Rect[]; notes: Rect[] };
        const jours = Array.from(document.querySelectorAll(".page--day"));
        const { photos, notes } = collecter(jours);
        return { photos, notes, pages: jours.length };
      },
      [COLLECTEUR_SOURCE],
    );

    const mesure = mesurerRatio(releve.photos, releve.notes, releve.pages);
    return {
      ratio: mesure.ratio,
      photos: mesure.photos,
      pages: releve.pages,
    };
  } finally {
    await page?.close();
  }
}

describe("le ratio texte / photo, mesuré sur le rendu", () => {
  for (const [nom, recit] of Object.entries(RECITS)) {
    for (const ratio of PHOTO_RATIOS) {
      it(`récit ${nom} à ${ratio} %`, async () => {
        const avant = etapeDe(recit);
        const recitAvant = recitDe(avant);
        const plan = photosRequired({ body_html: recit }, ratio, "a5", { funFacts: true });

        const apres = appliquerRatio(avant, ratio, { funFacts: true, decorations: true });

        // 1. Le récit du voyageur, identique octet pour octet. À 100 % il n'est
        //    pas imprimé du tout — c'est le seul palier où il ne se compare pas.
        if (ratio === 100) {
          expect(recitDe(apres)).toBe("");
        } else {
          expect(recitDe(apres)).toBe(recitAvant);
        }

        // 2. Le minimum de photos du palier.
        const posees = apres.reduce(
          (somme, jour) => somme + ((jour["photos"] as unknown[] | undefined)?.length ?? 0),
          0,
        );
        const minimum = MINIMUM_PHOTOS[ratio] ?? 0;
        expect(posees, "photos posées").toBeGreaterThanOrEqual(minimum);
        // Le PDF porte exactement le nombre que le chat a demandé.
        expect(posees, "le PDF porte le nombre annoncé dans le chat").toBe(plan.photos);

        // Le payload composé reste valide : ni texte perdu sur une planche, ni
        // page sans layout, ni légende trop longue.
        const validation = validatePayload({ book_title: "Mesure", days: apres });
        expect(validation.errors, JSON.stringify(validation.errors)).toEqual([]);

        // 3. Le ratio mesuré, dans la tolérance — ou le dépassement annoncé.
        const mesure = await mesurer({ book_title: "Mesure", render_profile: "print", days: apres });
        if (!mesure) {
          // Pas de navigateur : les deux premières vérifications ont tourné, la
          // troisième ne peut pas. On le dit plutôt que de faire croire au vert.
          console.warn("aucun Chromium disponible : le ratio mesuré n'a pas été vérifié");
          return;
        }

        expect(mesure.pages, "pages rendues").toBe(apres.length);

        const ecart = Math.abs(mesure.ratio - ratio);
        if (ecart > RATIO_TOLERANCE) {
          // Un dépassement hors tolérance est **admis seulement** quand le plan
          // l'avait annoncé : le minimum de photos du palier sur un récit trop
          // court pour l'absorber, ou des photos agrandies pour ne pas laisser
          // un quart de page blanc. Tout autre écart est une régression.
          expect(
            plan.depassementAssume || plan.remplissageForce,
            `ratio mesuré ${mesure.ratio} % pour une cible de ${ratio} % — ` +
              `non annoncé par le plan (${plan.raison})`,
          ).toBe(true);
        }
      }, 60_000);
    }
  }

});
