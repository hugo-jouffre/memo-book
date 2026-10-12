import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import sharp from "sharp";
import { describe, expect, it } from "vitest";

/**
 * La bibliothèque de stickers (`assets/stickers/`), préparée par
 * `scripts/preparer-stickers.ts` depuis la base Notion « Éléments
 * graphiques ». L'index doit dire vrai sur ses fichiers : le composeur
 * dimensionne les stickers d'après lui, sans ouvrir les images.
 */
const DOSSIER = resolve(import.meta.dirname, "../../assets/stickers");
const index = JSON.parse(readFileSync(resolve(DOSSIER, "stickers.json"), "utf8")) as {
  stickers: {
    fichier: string;
    famille: string;
    style: string;
    mots: string[];
    largeur: number;
    hauteur: number;
    maxPt: number;
    reserve?: string;
  }[];
};
const source = JSON.parse(readFileSync(resolve(DOSSIER, "source.json"), "utf8")) as {
  images: unknown[];
};

/** Des mots qui apparaissent dans presque tous les récits : un sticker qu'ils déclencheraient serait partout. */
const TROP_COURANTS = ["photo", "photos", "voyage", "jour", "matin", "soir", "ville", "carte", "sac", "vol", "bar", "van"];

describe("bibliothèque de stickers", () => {
  it("indexe chaque image du manifeste, une fois", () => {
    expect(index.stickers).toHaveLength(source.images.length);
    expect(new Set(index.stickers.map((s) => s.fichier)).size).toBe(index.stickers.length);
  });

  it("dit vrai sur chaque fichier : présent, aux dimensions annoncées, transparent", async () => {
    for (const s of index.stickers) {
      const chemin = resolve(DOSSIER, s.fichier);
      expect(existsSync(chemin), s.fichier).toBe(true);
      const meta = await sharp(chemin).metadata();
      expect([meta.width, meta.height], s.fichier).toEqual([s.largeur, s.hauteur]);
      expect(meta.hasAlpha, s.fichier).toBe(true);
      // 150 dpi au moins à la largeur maximale.
      expect(s.maxPt, s.fichier).toBe(Math.floor((s.largeur / 150) * 72));
    }
  });

  it("donne des mots déclencheurs précis à tout sticker que le composeur peut tirer", () => {
    for (const s of index.stickers) {
      expect(["sticker", "dessin", "trait"]).toContain(s.style);
      if (s.reserve) continue;
      expect(s.mots.length, s.fichier).toBeGreaterThan(0);
      for (const mot of s.mots) {
        expect(mot, `${s.fichier} : « ${mot} »`).toMatch(/^[a-z0-9 -]+$/);
        expect(TROP_COURANTS, `${s.fichier} : « ${mot} » est trop courant`).not.toContain(mot);
      }
    }
  });

  it("réserve les personnages de dos, à choisir d'après les voyageurs", () => {
    const personnages = index.stickers.filter((s) => s.famille === "personnage");
    expect(personnages.length).toBeGreaterThan(0);
    for (const p of personnages) expect(p.reserve).toBe("voyageurs");
  });
});
