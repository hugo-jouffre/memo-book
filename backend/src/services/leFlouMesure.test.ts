import { describe, expect, it } from "vitest";

import { blurOf } from "./photoAnalysis.js";

/**
 * **Le flou, mesuré pour de vrai** (T310).
 *
 * Ces tests tiennent sur des images **fabriquées**, pas sur des photos : un
 * damier a des bords dont on connaît la largeur, et on peut le flouter d'un
 * rayon choisi. Les chiffres relevés sur de vraies photos sont dans le
 * commentaire de ``blurOf`` — ils sont du même ordre (0,24 à 0,34 pour une
 * photo nette), mais ils ne peuvent pas servir de test : décoder trois JPEG
 * coûterait une seconde, et une photo n'a pas de vérité connue.
 *
 * Ce que ces tests protègent, c'est **ce que l'ancienne mesure faisait de
 * travers** : ne pas voir le flou, et condamner une image unie.
 */

const W = 240;
const H = 180;

/** Un damier de carreaux de `pas` pixels : des bords francs, partout. */
function damier(pas: number, { contraste = 1, lumiere = 1 } = {}): Uint8Array {
  const pixels = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y += 1) {
    for (let x = 0; x < W; x += 1) {
      const clair = (Math.floor(x / pas) + Math.floor(y / pas)) % 2 === 0;
      const valeur = Math.round((128 + (clair ? 1 : -1) * 100 * contraste) * lumiere);
      const i = (y * W + x) * 4;
      pixels[i] = valeur;
      pixels[i + 1] = valeur;
      pixels[i + 2] = valeur;
      pixels[i + 3] = 255;
    }
  }
  return pixels;
}

/** Flou de boîte, rayon `r`. Rend une copie. */
function flouter(source: Uint8Array, r: number): Uint8Array {
  const out = new Uint8Array(source);
  for (let y = 0; y < H; y += 1) {
    for (let x = 0; x < W; x += 1) {
      let somme = 0;
      let n = 0;
      for (let dy = -r; dy <= r; dy += 1) {
        for (let dx = -r; dx <= r; dx += 1) {
          const xx = x + dx;
          const yy = y + dy;
          if (xx < 0 || xx >= W || yy < 0 || yy >= H) continue;
          somme += source[(yy * W + xx) * 4]!;
          n += 1;
        }
      }
      const i = (y * W + x) * 4;
      const valeur = Math.round(somme / n);
      out[i] = valeur;
      out[i + 1] = valeur;
      out[i + 2] = valeur;
    }
  }
  return out;
}

const flou = (pixels: Uint8Array) => blurOf(pixels, W, H).blur;

describe("blurOf", () => {
  it("voit le flou, et plus il est fort plus elle le dit", () => {
    const net = flou(damier(20))!;
    const peu = flou(flouter(damier(20), 2))!;
    const beaucoup = flou(flouter(damier(20), 5))!;

    expect(net).toBeLessThan(0.2);
    expect(peu).toBeGreaterThan(0.4);
    expect(beaucoup).toBeGreaterThan(0.7);
    expect(net).toBeLessThan(peu);
    expect(peu).toBeLessThan(beaucoup);
  });

  it("se taît sur une image sans aucun bord, au lieu de l'accuser", () => {
    // Le reproche exact fait à l'ancienne mesure : un ciel uni, parfaitement
    // net, sortait `reject`. Ici il ne sort rien du tout.
    const uni = new Uint8Array(W * H * 4).fill(255);

    expect(blurOf(uni, W, H)).toEqual({ blur: null, edges: 0 });
  });

  it("ne confond pas le manque de contraste avec le flou", () => {
    // C'était l'erreur de fond : l'ancienne mesure *était* le contraste.
    // Celle-ci est un rapport, donc le contraste s'annule exactement.
    expect(flou(damier(20, { contraste: 0.4 }))).toBe(flou(damier(20)));
  });

  it("ne confond pas la nuit avec le flou", () => {
    expect(flou(damier(20, { lumiere: 0.12 }))).toBe(flou(damier(20)));
  });

  it("rend l'énergie des bords, qui est ce qui permettra de calibrer", () => {
    const net = blurOf(damier(20), W, H);
    const sombre = blurOf(damier(20, { lumiere: 0.12 }), W, H);

    // Le même jugement, des bords huit fois plus faibles : les deux chiffres
    // ne disent pas la même chose, et c'est pour ça qu'on garde les deux.
    expect(net.edges).toBeGreaterThan(sombre.edges * 5);
    expect(net.blur).toBe(sombre.blur);
  });

  it("⚠️ rate un motif plus fin que son re-flou, au lieu de l'accuser à tort", () => {
    // Limite connue et mesurée : quand le détail est plus petit que le rayon
    // du re-flou, le deuxième flou n'a presque plus rien à détruire, et la
    // mesure relit l'image comme nette. Un damier de 6 pixels flouté d'un
    // rayon de 3 rend 0,105, contre 0,035 net.
    //
    // Ça ne se produit pas sur une photo, qui porte toujours des détails de
    // plusieurs tailles — les trois photos réelles mesurées passent de 0,24-
    // 0,34 à 0,61-0,67 pour un flou de 2 pixels. Et le sens de l'erreur est
    // le bon : on **rate** un flou, on n'accuse pas une photo nette.
    const finNet = flou(damier(6))!;
    const finFlou = flou(flouter(damier(6), 3))!;

    expect(finNet).toBeLessThan(0.1);
    expect(finFlou).toBeLessThan(0.2);
  });
});
