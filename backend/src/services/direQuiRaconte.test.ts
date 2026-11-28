import { describe, expect, it } from "vitest";

import { bodyLength, pageCapacity, validatePayload } from "./payloadValidator.js";
import {
  ATTRIBUTION_CLASS,
  HeuristicStructurer,
  avecLesVoix,
  narrateursDe,
  type StructuringEntry,
} from "./structuring.js";

/**
 * **Dire qui raconte** (T317) : le prénom paraît quand la voix change, et
 * seulement si le carnet se raconte à plusieurs.
 */

function entry(overrides: Partial<StructuringEntry> = {}): StructuringEntry {
  return {
    kind: "audio",
    transcript: "On est arrivés ce matin.",
    editedByUser: false,
    title: null,
    funFact: null,
    funFactTitle: null,
    weatherKey: null,
    capturedAt: new Date("2026-04-12T09:00:00Z"),
    stepPlace: "Kyoto",
    photoUrl: null,
    ...overrides,
  };
}

const structurer = new HeuristicStructurer();

const carnet = (entries: StructuringEntry[]) =>
  structurer.structure({
    title: "Carnet",
    subtitle: null,
    authors: null,
    theme: null,
    coverPhotoUrl: null,
    entries,
    tripContext: null,
  });

const corps = (payload: Awaited<ReturnType<typeof carnet>>) =>
  (payload["days"] as Record<string, unknown>[])
    .map((day) => (typeof day["body_html"] === "string" ? day["body_html"] : ""))
    .join("");

/** Les prénoms attribués, dans l'ordre où le carnet les écrit. */
const prenomsDits = (html: string) =>
  [...html.matchAll(new RegExp(`<p class="${ATTRIBUTION_CLASS}">([^<]*)</p>`, "g"))].map(
    (trouve) => trouve[1],
  );

describe("narrateursDe", () => {
  it("compte les voix du carnet, sans doublon", () => {
    expect(
      narrateursDe([
        entry({ narrator: "Maÿlis" }),
        entry({ narrator: "Paul" }),
        entry({ narrator: "Maÿlis" }),
      ]),
    ).toEqual(["Maÿlis", "Paul"]);
  });

  it("ne compte pas la voix d'un souvenir sans récit", () => {
    // Une photo n'a pas de texte : elle ne raconte rien, donc elle ne fait
    // pas de ce carnet un carnet à deux voix.
    expect(
      narrateursDe([
        entry({ narrator: "Maÿlis" }),
        entry({ kind: "photo", transcript: null, narrator: "Paul" }),
      ]),
    ).toEqual(["Maÿlis"]);
  });
});

describe("dire qui raconte", () => {
  /**
   * **Le test qui porte la décision.** Un carnet à une seule voix suit le
   * chemin d'avant T317, et le suit à l'octet près : sans ça, tous les
   * carnets déjà composés changeraient de mise en page pour rien.
   */
  it("n'écrit aucun prénom dans un carnet à une voix, et rend le même récit qu'avant", async () => {
    const textes = [
      entry({ transcript: "Le marché sentait le poisson grillé." }),
      entry({ transcript: "On a marché jusqu'au temple, tout en haut." }),
    ];

    const sansPersonne = corps(await carnet(textes));
    const uneSeuleVoix = corps(
      await carnet(textes.map((item) => ({ ...item, narrator: "Maÿlis" }))),
    );

    expect(prenomsDits(uneSeuleVoix)).toEqual([]);
    expect(uneSeuleVoix).toBe(sansPersonne);
  });

  it("écrit le prénom au changement de voix, et pas deux fois de suite", async () => {
    const html = corps(
      await carnet([
        entry({ transcript: "Le marché sentait le poisson grillé.", narrator: "Maÿlis" }),
        entry({ transcript: "J'ai goûté l'anguille, contre mon gré.", narrator: "Maÿlis" }),
        entry({ transcript: "Moi j'ai attendu dehors, à l'ombre.", narrator: "Paul" }),
        entry({ transcript: "Et on est repartis à pied.", narrator: "Maÿlis" }),
      ]),
    );

    // Maÿlis une fois pour ses deux souvenirs d'affilée, puis Paul, puis
    // Maÿlis de nouveau : trois attributions pour quatre souvenirs.
    expect(prenomsDits(html)).toEqual(["Maÿlis", "Paul", "Maÿlis"]);
  });

  it("ne laisse jamais un paragraphe porter deux voix", async () => {
    const html = corps(
      await carnet([
        entry({ transcript: "Court.", narrator: "Maÿlis" }),
        entry({ transcript: "Court aussi.", narrator: "Paul" }),
      ]),
    );

    // Deux phrases très courtes : avant T317 elles tenaient dans un seul
    // paragraphe, puisque les paragraphes se remplissaient au nombre de
    // signes. Chacune a maintenant le sien, derrière son prénom.
    expect(html).toContain(`<p class="${ATTRIBUTION_CLASS}">Maÿlis</p><p>Court.</p>`);
    expect(html).toContain(`<p class="${ATTRIBUTION_CLASS}">Paul</p><p>Court aussi.</p>`);
  });

  it("rappelle la voix en tête de chaque page", async () => {
    // Un récit assez long pour déborder sur une page de suite.
    const long = "Une phrase qui occupe sa place dans le récit de la journée. ".repeat(40);
    const payload = await carnet([
      entry({ transcript: long, narrator: "Maÿlis" }),
      entry({ transcript: "Moi j'ai dormi.", narrator: "Paul" }),
    ]);
    const days = payload["days"] as Record<string, unknown>[];
    const pages = days.filter((day) => typeof day["body_html"] === "string" && day["body_html"]);

    expect(pages.length).toBeGreaterThan(1);
    // Chaque page nomme la voix par laquelle elle commence : un lecteur qui
    // tourne la page ne doit pas avoir à remonter pour savoir qui parle.
    for (const page of pages) {
      expect(prenomsDits(page["body_html"] as string).length).toBeGreaterThan(0);
    }
  });

  /**
   * **L'invariant qui tient tout le ticket**, et qu'il a fallu voir sur un
   * carnet rendu pour l'écrire.
   *
   * Une première version se taisait quand il ne restait pas la place de
   * nommer la nouvelle voix, en laissant le récit continuer. Sur la page
   * rendue, le texte de Paul se retrouvait juste sous le prénom de Maÿlis :
   * **lu comme du Maÿlis**. Un prénom qui manque n'est pas une gêne, c'est
   * une fausse attribution.
   *
   * La règle est donc : dans une page, un paragraphe est soit précédé de son
   * prénom, soit de la même voix que celui d'avant. Quand on ne peut pas
   * nommer, la page s'arrête et la voix commence la suivante.
   */
  it("ne laisse jamais le texte d'une voix se lire sous le prénom d'une autre", async () => {
    const long = "Une phrase qui occupe sa place dans le récit de la journée. ".repeat(9);
    const payload = await carnet([
      entry({ transcript: long, narrator: "Maÿlis" }),
      entry({ transcript: "Oui.", narrator: "Paul" }),
    ]);
    const pages = (payload["days"] as Record<string, unknown>[])
      .map((day) => day["body_html"])
      .filter((html): html is string => typeof html === "string" && html.length > 0);

    for (const page of pages) {
      // Les morceaux de la page, dans l'ordre : un prénom, ou un paragraphe.
      const morceaux = [...page.matchAll(/<p(?: class="([^"]*)")?>([\s\S]*?)<\/p>/g)];
      let nomme = false;
      for (const [, classe] of morceaux) {
        if (classe === ATTRIBUTION_CLASS) {
          nomme = true;
          continue;
        }
        // Le premier paragraphe d'une page doit être nommé, et tout
        // paragraphe qui suit un prénom appartient à ce prénom.
        expect(nomme).toBe(true);
      }
    }

    // Et le souvenir de Paul n'est jamais perdu pour une question de place.
    expect(pages.join("")).toContain("Oui.");
  });

  it("produit un payload que le validateur accepte", async () => {
    const payload = await carnet([
      entry({ transcript: "Le marché sentait le poisson grillé.", narrator: "Maÿlis" }),
      entry({ transcript: "Moi j'ai attendu dehors.", narrator: "Paul" }),
    ]);

    const resultat = validatePayload(payload);
    expect(resultat.errors).toEqual([]);
    expect(resultat.valid).toBe(true);
  });
});

/**
 * **La passe qui repose les prénoms sur un carnet arrangé par le modèle.**
 *
 * En production, les pages sont montées par un modèle qui ne sait rien des
 * attributions. Cette passe les retrouve en cherchant le texte de chaque
 * paragraphe dans les souvenirs du carnet.
 */
describe("avecLesVoix", () => {
  const souvenirs = [
    entry({ transcript: "Le marché sentait le poisson grillé.", narrator: "Maÿlis" }),
    entry({ transcript: "Moi j'ai attendu dehors, à l'ombre.", narrator: "Paul" }),
  ];

  /** Une page telle que le modèle la rend : un layout, et des paragraphes. */
  const page = (...paragraphes: string[]) => ({
    days: [
      {
        title: "Kyoto",
        day_intro: { day_number: "01", location: "Kyoto", date: "12 avr." },
        layout_recit_photo: true,
        body_html: paragraphes.map((texte) => `<p>${texte}</p>`).join(""),
      },
    ],
  });

  const recitDe = (payload: Record<string, unknown>) =>
    ((payload["days"] as Record<string, unknown>[])[0]!["body_html"] as string) ?? "";

  it("pose le prénom devant le paragraphe de chaque voix", () => {
    const sortie = avecLesVoix(
      page("Le marché sentait le poisson grillé.", "Moi j'ai attendu dehors, à l'ombre."),
      souvenirs,
    );

    expect(prenomsDits(recitDe(sortie))).toEqual(["Maÿlis", "Paul"]);
  });

  it("retrouve un souvenir que le modèle a découpé en deux paragraphes", () => {
    // Découper n'est pas réécrire : les deux morceaux appartiennent au même
    // souvenir, donc un seul prénom.
    const sortie = avecLesVoix(page("Le marché sentait", "le poisson grillé."), souvenirs);

    expect(prenomsDits(recitDe(sortie))).toEqual(["Maÿlis"]);
  });

  it("ne nomme personne devant un paragraphe qui mêle deux souvenirs", () => {
    // Le modèle a le droit de les réunir ; aucun prénom n'est alors vrai pour
    // tout le paragraphe.
    const sortie = avecLesVoix(
      page("Le marché sentait le poisson grillé. Moi j'ai attendu dehors, à l'ombre."),
      souvenirs,
    );

    expect(prenomsDits(recitDe(sortie))).toEqual([]);
  });

  it("ne nomme personne devant un texte qui ne vient d'aucun souvenir", () => {
    // Si les mots ont changé, on ne sait plus qui les a dits.
    const sortie = avecLesVoix(page("Une phrase que personne n'a prononcée."), souvenirs);

    expect(prenomsDits(recitDe(sortie))).toEqual([]);
  });

  it("repasse sans rien changer de plus", () => {
    const une = avecLesVoix(
      page("Le marché sentait le poisson grillé.", "Moi j'ai attendu dehors, à l'ombre."),
      souvenirs,
    );
    const deux = avecLesVoix(une, souvenirs);

    expect(recitDe(deux)).toBe(recitDe(une));
  });

  it("n'écrit aucun prénom dans un carnet à une voix, et retire ceux qui traînent", () => {
    const invente = {
      days: [
        {
          title: "Kyoto",
          day_intro: { day_number: "01", location: "Kyoto", date: "12 avr." },
          layout_recit_photo: true,
          body_html: `<p class="${ATTRIBUTION_CLASS}">Maÿlis</p><p>Le marché sentait le poisson grillé.</p>`,
        },
      ],
    };

    const sortie = avecLesVoix(invente, [souvenirs[0]!]);

    expect(prenomsDits(recitDe(sortie))).toEqual([]);
    expect(recitDe(sortie)).toBe("<p>Le marché sentait le poisson grillé.</p>");
  });

  it("ne pose aucun prénom sur une page que le modèle a remplie à ras bord", () => {
    // Le modèle a rempli la page sans savoir que des lignes s'ajouteraient :
    // un prénom qui ne tient pas n'est pas écrit, plutôt que de pousser le
    // récit sous la marge.
    const phrase = "Le marché sentait le poisson grillé, encore et encore.";
    // Deux paragraphes du **même** souvenir : le modèle a le droit de le
    // découper, et chacun reste sous la taille maximale d'un paragraphe.
    const debut = [phrase, phrase, phrase, phrase].join(" ");
    const suite = [phrase, phrase, phrase, phrase].join(" ");
    const paul = "Moi j'ai attendu dehors, à l'ombre, longtemps.";
    const souvenirsLongs = [
      entry({ transcript: `${debut} ${suite}`, narrator: "Maÿlis" }),
      entry({ transcript: paul, narrator: "Paul" }),
    ];
    const pleine = page(debut, suite, paul);
    const jour = (pleine["days"] as Record<string, unknown>[])[0]!;

    // Le récit **tient** dans la page, et il ne reste pas les 100 signes d'un
    // prénom : le carnet préfère ne nommer personne que pousser le récit sous
    // la marge.
    expect(bodyLength(jour)).toBeLessThanOrEqual(pageCapacity(jour));
    expect(pageCapacity(jour) - bodyLength(jour)).toBeLessThan(100);
    expect(prenomsDits(recitDe(avecLesVoix(pleine, souvenirsLongs)))).toEqual([]);
  });
});
