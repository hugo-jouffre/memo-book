#!/usr/bin/env tsx
/**
 * **Essayer un sticker sur une vraie photo**, sans monter le back-end ni
 * composer un carnet.
 *
 *   npx tsx scripts/essayer-un-sticker.ts <photo> [dossier de sortie]
 *
 * La chaîne entière, en vrai : l'œil (`stickerVision.ts`, un appel à OpenAI —
 * moins d'un demi-centime) puis les ciseaux (`stickerCut.ts`, local). Il écrit
 * trois fichiers : ce qu'on a montré au modèle, le sticker seul, et le sticker
 * posé sur une page crème — c'est celle-là qu'on regarde pour juger.
 *
 * ⚠️ Il appelle le **vrai** modèle : `OPENAI_API_KEY` doit être dans `.env`.
 * Sans clé, l'œil est aveugle (`BlindStickerSpotter`) et ne rend rien, ce que
 * le script dit au lieu d'échouer.
 *
 * C'est le seul endroit où l'on vérifie le repérage : il ne se teste pas en
 * suite (il faudrait une vraie photo et une clé), et une suite qui appelle un
 * modèle n'est plus une suite. Les ciseaux, eux, sont tenus par
 * `test/stickerCut.test.ts`.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import sharp from "sharp";
import { loadEnv } from "../src/env.js";
import { toRenderablePhoto } from "../src/services/photoFormat.js";
import { cutSticker } from "../src/services/stickerCut.js";
import { refineCorners } from "../src/services/stickerEdges.js";
import { createStickerSpotter, STICKER_VISION_SIDE } from "../src/services/stickerVision.js";

const [chemin, sortie = "/tmp"] = process.argv.slice(2);
if (!chemin) {
  console.error("Usage : npx tsx scripts/essayer-un-sticker.ts <photo> [dossier de sortie]");
  process.exit(1);
}

const env = loadEnv();
if (!env.live) {
  console.error("Pas de OPENAI_API_KEY dans .env : l'œil est aveugle, il n'y a rien à essayer.");
  process.exit(1);
}

// Comme le ferait la chaîne : les octets d'abord rendus lisibles — `sharp` ne
// décode pas le HEIC d'un iPhone.
const { buffer: photo, converted } = await toRenderablePhoto(
  readFileSync(resolve(chemin)),
  basename(chemin),
  "image/jpeg",
);
const taille = await sharp(photo).metadata();
console.log(`photo : ${taille.width} × ${taille.height}${converted ? " (HEIC converti)" : ""}`);

const vue = await sharp(photo)
  .rotate()
  .resize({ width: STICKER_VISION_SIDE, height: STICKER_VISION_SIDE, fit: "inside" })
  .jpeg({ quality: 70 })
  .toBuffer();
writeFileSync(`${sortie}/essai-vue-du-modele.jpg`, vue);

const spots = await createStickerSpotter(env).spot([{ id: "photo-1", jpeg: vue }]);
if (spots.length === 0) {
  console.log("L'œil n'a rien retenu : pas de souvenir plat, ou pas assez net.");
  process.exit(0);
}

const [spot] = spots;
console.log(`repéré : « ${spot!.label} », score ${spot!.score}`);
console.log("coins  :", spot!.corners.map((c) => `${c.x.toFixed(2)},${c.y.toFixed(2)}`).join("  "));

const resserres = await refineCorners(photo, spot!.corners);
console.log(
  resserres
    ? `resserré : ${resserres.map((c) => `${c.x.toFixed(2)},${c.y.toFixed(2)}`).join("  ")}`
    : "resserrage : les pixels n'ont pas conclu, on garde les coins du modèle.",
);

const sticker = await cutSticker(photo, resserres ?? spot!.corners);
writeFileSync(`${sortie}/essai-sticker.png`, sticker.png);

// Posé sur une page crème, avec un faux récit : un sticker se juge sur la page.
const page = await sharp({
  create: { width: 900, height: 900, channels: 4, background: { r: 252, g: 242, b: 233, alpha: 1 } },
})
  .composite([
    {
      input: Buffer.from(
        `<svg width="900" height="900">${Array.from(
          { length: 7 },
          (_, i) =>
            `<rect x="70" y="${90 + i * 26}" width="${i === 6 ? 300 : 560}" height="9" rx="4" fill="#1b1b1b" opacity="0.12"/>`,
        ).join("")}</svg>`,
      ),
    },
    {
      input: await sharp(sticker.png).resize({ width: 520, height: 520, fit: "inside" }).toBuffer(),
      top: 300,
      left: 90,
    },
  ])
  .png()
  .toBuffer();
writeFileSync(`${sortie}/essai-sur-la-page.png`, page);
console.log(`sticker : ${sticker.width} × ${sticker.height} → ${sortie}/essai-sur-la-page.png`);
