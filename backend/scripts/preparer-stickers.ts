#!/usr/bin/env tsx
/**
 * Prépare la bibliothèque de stickers du carnet (`assets/stickers/`).
 *
 * La source de dessin est la base Notion « Éléments graphiques ». On y
 * télécharge les images (une par page, nommée `<id de la page Notion>.png`)
 * dans un dossier de travail, puis :
 *
 *   npx tsx scripts/preparer-stickers.ts --brut <dossier des PNG téléchargés>
 *
 * Pour chaque entrée de `assets/stickers/source.json`, le script :
 *
 * - rogne les marges transparentes (le placement se cale sur le dessin, pas
 *   sur un cadre vide) ;
 * - garde la définition d'origine — on ne suréchantillonne pas : un PNG de
 *   300 px reste un PNG de 300 px ;
 * - écrit `assets/stickers/<famille>-<n>.png`, compressé ;
 * - relève largeur, hauteur et la largeur imprimable maximale à 150 dpi
 *   (`maxPt`), que le composeur ne dépasse jamais.
 *
 * Il réécrit ensuite `assets/stickers/stickers.json`, l'index que lit
 * l'atelier (`chargerStickers`, `app.js`). Les mots déclencheurs se règlent
 * par famille dans `source.json`, pas ici.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import sharp from "sharp";

const DOSSIER = resolve(import.meta.dirname, "../../assets/stickers");
/**
 * Définition minimale à l'impression : au-delà, le dessin se pixellise. 150 et
 * non les 200 des photos : un petit dessin décoratif le supporte, et les
 * exports de Notion (300 px pour la plupart, une fois rognés de 140 à 280 px)
 * ne donneraient à 200 dpi que des stickers de 2 à 3 cm. Des exports de 600 px
 * et plus permettraient de les agrandir.
 */
const DPI_MIN = 150;

interface Source {
  familles: Record<string, string[]>;
  reserves?: Record<string, string>;
  images: { notion: string; nom: string; famille: string; style: "sticker" | "dessin" | "trait" }[];
}

const args = process.argv.slice(2);
const i = args.indexOf("--brut");
const brut = i >= 0 ? args[i + 1] : undefined;
if (!brut) {
  console.error("Usage : npx tsx scripts/preparer-stickers.ts --brut <dossier des PNG téléchargés de Notion>");
  process.exit(1);
}

const source = JSON.parse(readFileSync(resolve(DOSSIER, "source.json"), "utf8")) as Source;
const parFamille = new Map<string, number>();
const stickers = [];

for (const image of source.images) {
  const chemin = resolve(brut, `${image.notion}.png`);
  if (!existsSync(chemin)) throw new Error(`image manquante : ${chemin} (${image.nom})`);
  const n = (parFamille.get(image.famille) ?? 0) + 1;
  parFamille.set(image.famille, n);
  const fichier = `${image.famille}-${n}.png`;

  const { data, info } = await sharp(chemin)
    .trim({ threshold: 1 })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer({ resolveWithObject: true });
  writeFileSync(resolve(DOSSIER, fichier), data);

  const reserve = source.reserves?.[image.famille];
  stickers.push({
    fichier,
    nom: image.nom,
    famille: image.famille,
    style: image.style,
    mots: source.familles[image.famille] ?? [],
    largeur: info.width,
    hauteur: info.height,
    maxPt: Math.floor((info.width / DPI_MIN) * 72),
    ...(reserve ? { reserve } : {}),
    notion: image.notion,
  });
}

writeFileSync(
  resolve(DOSSIER, "stickers.json"),
  `${JSON.stringify(
    {
      commentaire:
        "Généré par backend/scripts/preparer-stickers.ts depuis source.json — ne pas modifier à la main. " +
        "Format : voir assets/README.md § « assets/stickers/ ».",
      stickers,
    },
    null,
    2,
  )}\n`,
);
console.log(`${stickers.length} stickers, ${parFamille.size} familles → ${DOSSIER}`);
