import { Jimp } from "jimp";

/**
 * Des photos factices, pour dérouler le chat sans photothèque — le bouton
 * « Photos de test » (Hugo, 01/10/2026). **Jamais en production** : la puce
 * n'y est pas proposée, et le job refuse la commande.
 *
 * Des aplats de couleurs différentes, au format d'une photo d'iPhone réduite :
 * assez pour que la bulle, l'aperçu et la mise en page aient de vraies images.
 */
const PALETTE = [0xe0605eff, 0xd9924cff, 0xc9c24aff, 0x7fbf4dff, 0x3fae7aff, 0x3fa7d6ff] as const;

export async function samplePhotoJpegs(count: number): Promise<Buffer[]> {
  return Promise.all(
    Array.from({ length: count }, (_, index) =>
      new Jimp({ width: 1200, height: 900, color: PALETTE[index % PALETTE.length]! }).getBuffer("image/jpeg"),
    ),
  );
}
