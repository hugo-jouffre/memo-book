import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  FALLBACK_SOURCE,
  MANIFEST_FILE,
  buildManifest,
  parsePreviewName,
  publishedName,
  readSources,
  serializeManifest,
} from "../scripts/customisation-previews.js";

const DEFAULT_NAME =
  "Pointillés=on, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Playfair Display - Hansley - Gloria Hallelujah.png";

describe("aperçus de personnalisation", () => {
  it("lit les cinq réglages dans les noms du modèle", () => {
    expect(parsePreviewName(DEFAULT_NAME)).toEqual({
      rulesEnabled: true,
      photoTextRatio: 50,
      funFactsEnabled: true,
      decorationQuota: 2,
      fontCombo: "travel-journal",
    });
  });

  it("reconnaît « Hellelujah », la faute figée dans les noms de l'assortiment Manuscrit", () => {
    const name = "Pointillés=off, Ratio image=0%, Fun fact=off, Stickers=0, Typos=Hansley - Gloria Hellelujah.png";
    expect(parsePreviewName(name).fontCombo).toBe("handwritten");
  });

  it("lit un nom arrivé en NFD, comme un fichier glissé depuis le Finder", () => {
    expect(parsePreviewName(DEFAULT_NAME.normalize("NFD")).rulesEnabled).toBe(true);
  });

  it("refuse un assortiment inconnu plutôt que de l'ignorer", () => {
    expect(() =>
      parsePreviewName("Pointillés=off, Ratio image=0%, Fun fact=off, Stickers=0, Typos=Montserrat.png"),
    ).toThrow(/FONT_COMBOS/);
  });

  it("refuse deux sources pour la même combinaison", () => {
    const sources = [
      { name: DEFAULT_NAME, bytes: Buffer.from("a") },
      { name: DEFAULT_NAME.normalize("NFD"), bytes: Buffer.from("b") },
      { name: FALLBACK_SOURCE, bytes: Buffer.from("c") },
    ];
    expect(() => buildManifest(sources)).toThrow(/même combinaison/);
  });

  it("nomme une image d'après sa source : mêmes octets, même nom", () => {
    expect(publishedName(Buffer.from("x"))).toBe(publishedName(Buffer.from("x")));
    expect(publishedName(Buffer.from("x"))).not.toBe(publishedName(Buffer.from("y")));
  });

  // Le garde-fou de « ajouter un aperçu sans toucher au code » : un PNG déposé
  // sans relancer la chaîne ferait tomber ce test, et la CI avec.
  it("le manifeste versionné correspond aux PNG du dossier", () => {
    expect(readFileSync(MANIFEST_FILE, "utf8")).toBe(serializeManifest(buildManifest(readSources())));
  });
});
