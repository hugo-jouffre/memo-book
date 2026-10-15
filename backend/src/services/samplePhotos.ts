import { Jimp } from "jimp";

/**
 * Des photos factices, pour dérouler le chat sans photothèque — le bouton
 * « Photos de test » (Hugo, 01/10/2026). **Jamais en production** : la puce
 * n'y est pas proposée, et le job refuse la commande.
 *
 * Des aplats de couleurs différentes, au format d'une photo d'iPhone réduite :
 * assez pour que la bulle, l'aperçu et la mise en page aient de vraies images.
 *
 * **Paysage et portrait, en alternance** (Hugo, 15/10/2026). Elles étaient
 * toutes en 1200 × 900 : la couverture d'un voyage étant la plus récente de ses
 * photos **paysage** (`services/photoOrientation.ts`), le bouton de test ne
 * montrait jamais le cas du voyage qui n'a que des portraits et garde son
 * motif. Une photothèque réelle a les deux ; celle-ci aussi, en commençant par
 * un paysage pour qu'une seule photo suffise à voir une couverture arriver.
 */
const PALETTE = [0xe0605eff, 0xd9924cff, 0xc9c24aff, 0x7fbf4dff, 0x3fae7aff, 0x3fa7d6ff] as const;

/** Le format d'une photo d'iPhone réduite, dans les deux sens. */
const LANDSCAPE = { width: 1200, height: 900 } as const;
const PORTRAIT = { width: 900, height: 1200 } as const;

export async function samplePhotoJpegs(count: number): Promise<Buffer[]> {
  return Promise.all(
    Array.from({ length: count }, (_, index) => {
      const { width, height } = index % 2 === 0 ? LANDSCAPE : PORTRAIT;
      return new Jimp({ width, height, color: PALETTE[index % PALETTE.length]! }).getBuffer("image/jpeg");
    }),
  );
}
