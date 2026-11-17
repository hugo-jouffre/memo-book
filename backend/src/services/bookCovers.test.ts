import { describe, expect, it } from "vitest";
import { assertNoNullValues } from "./bookPdf.js";
import { bookCoversOf, coverPhotoEntryIds, type CoverMemo } from "./bookCovers.js";

const env = { API_PUBLIC_BASE_URL: "https://api.memo-book.test" } as never;

const PHOTOS = new Map<string, string>([
  ["un", "https://cdn.test/un.jpg"],
  ["deux", "https://cdn.test/deux.jpg"],
]);

function carnet(front: Record<string, unknown>, back: Record<string, unknown> = {}): CoverMemo {
  return {
    coverFront: { styleId: "front-default", title: "", subtitle: "", photoId: null, statIds: [], ...front },
    coverBack: { styleId: "back-default", title: "", subtitle: "", photoId: null, statIds: [], ...back },
    startDate: new Date("2026-08-02T00:00:00.000Z"),
    endDate: new Date("2026-08-09T00:00:00.000Z"),
    dayCount: 8,
    distanceKilometres: 2340,
    destinationCountryCode: "JP",
    memoryCount: 12,
    photoCount: 40,
    coverPhotos: [],
    steps: [{ destinationCountryCode: "KR", transport: "train" }],
  };
}

const platsDe = (memo: CoverMemo) => bookCoversOf(env, memo, PHOTOS, 40);

describe("les plats du carnet", () => {
  it("dessine le gabarit choisi, et celui d'avant les gabarits reste reconnaissable", () => {
    expect(platsDe(carnet({ styleId: "front-travel-book" })).front.family).toBe("travel-book");
    // Un carnet réglé avant le 08/10/2026 : « front-kraft » est devenu Dessin.
    expect(platsDe(carnet({ styleId: "front-kraft" })).front.family).toBe("drawing");
    // Et un style inventé ne laisse pas le carnet sans couverture.
    expect(platsDe(carnet({ styleId: "front-inconnu" })).front.family).toBe("default");
  });

  it("lit la signature en deux temps — qui, puis quand", () => {
    const deux = platsDe(carnet({ subtitle: "Maylis et Claire\nAoût 2026" })).front;
    expect(deux.authors).toBe("Maylis et Claire");
    expect(deux.when).toBe("Août 2026");

    // Une seule ligne : c'est le « quand », comme dans l'app — les gabarits qui
    // posent la date la trouvent, ceux qui posent les voyageurs n'écrivent rien.
    const une = platsDe(carnet({ subtitle: "Août 2026" })).front;
    expect(une.authors).toBeUndefined();
    expect(une.when).toBe("Août 2026");
  });

  it("n'imprime au dos que le texte que ce gabarit porte", () => {
    const mots = { subtitle: "Ce carnet garde ce qu'une photo ne garde pas." };
    // « Par défaut » tient sur son trajet et ses chiffres, « Travel book » sur
    // sa photo encadrée : l'app grise le champ, le gabarit ne l'imprime pas.
    expect(platsDe(carnet({}, { styleId: "back-default", ...mots })).back.text).toBe("");
    expect(platsDe(carnet({}, { styleId: "back-travel-book", ...mots })).back.text).toBe("");
    expect(platsDe(carnet({}, { styleId: "back-elegant", ...mots })).back.text).toBe(mots.subtitle);
  });

  it("ne pose les chiffres que sur les deux dos qui les portent, et dans l'ordre choisi", () => {
    const choisis = { statIds: ["stat-countries", "stat-days"] };
    const defaut = platsDe(carnet({}, { styleId: "back-default", ...choisis })).back;
    expect(defaut.stats.map((stat) => stat.value)).toEqual(["2", "8"]);
    // Le libellé arrive coupé : c'est le serveur qui écrit « pays / visités ».
    expect(defaut.stats[0]?.lines).toEqual(["pays", "visités"]);

    expect(platsDe(carnet({}, { styleId: "back-assouline", ...choisis })).back.stats).toHaveLength(2);
    expect(platsDe(carnet({}, { styleId: "back-elegant", ...choisis })).back.stats).toEqual([]);
    // Un chiffre que ce voyage ne sait pas calculer n'apparaît pas.
    const sansRien = carnet({}, { styleId: "back-default", statIds: ["stat-inconnu"] });
    expect(platsDe(sansRien).back.stats).toEqual([]);
  });

  it("sert la photo d'un souvenir par l'adresse que la composition a préparée", () => {
    const plats = platsDe(carnet({ photoId: "entry-deux" }));
    expect(plats.front.photo).toBe("https://cdn.test/deux.jpg");
    // La choisie d'abord : c'est elle qui ouvre les timbres et les vignettes.
    expect(plats.front.gallery[0]).toBe("https://cdn.test/deux.jpg");
    expect(plats.front.gallery).toHaveLength(2);
  });

  it("sert une photo importée pour la couverture par sa route publique", () => {
    const memo = carnet({ photoId: "7f3c" });
    memo.coverPhotos = [{ id: "7f3c", storageKey: "covers/7f3c.jpg" }];
    expect(platsDe(memo).front.photo).toBe("https://api.memo-book.test/v1/cover-photos/7f3c.jpg");
  });

  it("apparie chaque temps du récit de quatrième à une image, en tournant", () => {
    const memo = carnet({}, { styleId: "back-watercolor", subtitle: "Un.\n\nDeux.\n\nTrois." });
    const temps = platsDe(memo).back.paragraphs;
    expect(temps.map((t) => t.text)).toEqual(["Un.", "Deux.", "Trois."]);
    expect(temps.map((t) => t.photo)).toEqual([
      "https://cdn.test/un.jpg",
      "https://cdn.test/deux.jpg",
      "https://cdn.test/un.jpg",
    ]);
  });

  it("réduit un titre trop long plutôt que de le laisser déborder du papier", () => {
    expect(platsDe(carnet({ title: "Japon" })).front.titleScale).toBe(1);
    const long = platsDe(carnet({ title: "Notre tour du Japon et de la Corée" })).front;
    expect(long.titleScale).toBeLessThan(1);
    // Jamais au point d'être illisible : le plancher tient.
    const interminable = platsDe(carnet({ title: "x".repeat(500) })).front;
    expect(interminable.titleScale).toBe(0.4);
  });

  it("n'envoie jamais de `null` au gabarit, qui l'imprimerait « None »", () => {
    // Le piège de Jinja2 (`bookPdf.ts`) : un plat sans photo, sans signature et
    // sans chiffres est le cas le plus nu, et c'est là qu'un null se glisse.
    expect(() => assertNoNullValues(platsDe(carnet({})))).not.toThrow();
    const rempli = carnet(
      { photoId: "entry-un", title: "Japon", subtitle: "Maylis\nAoût 2026" },
      { styleId: "back-assouline", subtitle: "Deux mots.", statIds: ["stat-days"] },
    );
    expect(() => assertNoNullValues(platsDe(rempli))).not.toThrow();
  });

  it("nomme les souvenirs dont une photo est posée sur un plat", () => {
    const memo = carnet({ photoId: "entry-un" }, { photoId: "entry-deux" });
    expect(coverPhotoEntryIds(memo)).toEqual(["un", "deux"]);
    // Une photo importée pour la couverture n'est pas un souvenir du voyage.
    expect(coverPhotoEntryIds(carnet({ photoId: "7f3c" }))).toEqual([]);
  });
});
