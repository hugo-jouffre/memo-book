import { describe, expect, it } from "vitest";
import { validatePayload } from "./payloadValidator.js";
import {
  groupEntriesByDay,
  HeuristicStructurer,
  pickLayout,
  type StructuringEntry,
} from "./structuring.js";

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
    placeLabel: "Kyoto",
    photoUrl: null,
    ...overrides,
  };
}

describe("groupEntriesByDay", () => {
  it("regroupe les entrées d'une même journée", () => {
    const groups = groupEntriesByDay([
      entry({ capturedAt: new Date("2026-04-12T09:00:00Z") }),
      entry({ capturedAt: new Date("2026-04-12T20:30:00Z") }),
      entry({ capturedAt: new Date("2026-04-13T08:00:00Z") }),
    ]);

    expect(groups).toHaveLength(2);
    expect(groups[0]?.entries).toHaveLength(2);
    expect(groups[1]?.entries).toHaveLength(1);
  });

  it("remet les entrées dans l'ordre chronologique", () => {
    const groups = groupEntriesByDay([
      entry({ capturedAt: new Date("2026-04-14T08:00:00Z"), transcript: "troisième" }),
      entry({ capturedAt: new Date("2026-04-12T08:00:00Z"), transcript: "premier" }),
      entry({ capturedAt: new Date("2026-04-13T08:00:00Z"), transcript: "deuxième" }),
    ]);

    expect(groups.map((group) => group.entries[0]?.transcript)).toEqual([
      "premier",
      "deuxième",
      "troisième",
    ]);
  });

  it("ne produit rien pour une liste vide", () => {
    expect(groupEntriesByDay([])).toEqual([]);
  });
});

describe("pickLayout", () => {
  it("suit l'heuristique de LAYOUT_KB", () => {
    // Sous le minimum de S, c'est l'image qui porte la page.
    expect(pickLayout(4, 100)).toBe("layout_photo_page");
    expect(pickLayout(1, 100)).toBe("layout_hero_top");
    // Sans photo ni carte, aucun layout ne respire : on reste sur le récit.
    expect(pickLayout(0, 100)).toBe("layout_story_facts");

    // Au-dessus, le plus visuel de ceux qui tiennent le texte.
    expect(pickLayout(0, 200)).toBe("layout_story_opener");
    expect(pickLayout(2, 300)).toBe("layout_split_left");
    expect(pickLayout(4, 300)).toBe("layout_collage");
    // `layout_hero_top` plafonne à 380 caractères : au-delà il faut du récit
    // pleine largeur.
    expect(pickLayout(1, 300)).toBe("layout_hero_top");
    expect(pickLayout(1, 900)).toBe("layout_story_opener");
  });
});

describe("HeuristicStructurer", () => {
  const structurer = new HeuristicStructurer();

  it("produit un payload conforme au schéma du dépôt", async () => {
    const payload = await structurer.structure({
      title: "Notre tour du monde",
      subtitle: "Raconté à la voix",
      authors: "Claire et Gus",
      theme: "voyage",
      coverPhotoUrl: "https://cdn.example.test/cover.jpg",
      entries: [
        entry({ capturedAt: new Date("2026-04-12T09:00:00Z") }),
        entry({
          kind: "photo",
          transcript: null,
          capturedAt: new Date("2026-04-12T10:00:00Z"),
          photoUrl: "https://cdn.example.test/photo-1.jpg",
        }),
        entry({
          capturedAt: new Date("2026-04-13T09:00:00Z"),
          transcript: "Deuxième journée, on a marché longtemps.",
          placeLabel: "Nara",
        }),
      ],
    });

    expect(validatePayload(payload)).toMatchObject({ valid: true, errors: [] });
    expect(payload["days"]).toHaveLength(2);
    expect(payload["book_title"]).toBe("Notre tour du monde");
    expect(payload["cover_photo"]).toBe("https://cdn.example.test/cover.jpg");
  });

  it("découpe un récit long en paragraphes qui tiennent dans la page", async () => {
    const longSentence = `${"Nous avons marché le long du fleuve. ".repeat(40)}`;

    const payload = await structurer.structure({
      title: "Carnet",
      subtitle: null,
      authors: null,
      theme: null,
      coverPhotoUrl: null,
      entries: [entry({ transcript: longSentence })],
    });

    // La preuve utile n'est pas le nombre de paragraphes mais le fait que le
    // validateur — celui qui protège de la page qui déborde — soit satisfait.
    expect(validatePayload(payload).errors).toEqual([]);
  });

  it("rattache chaque photo à la bonne journée", async () => {
    const payload = await structurer.structure({
      title: "Carnet",
      subtitle: null,
      authors: null,
      theme: null,
      coverPhotoUrl: null,
      entries: [
        entry({ capturedAt: new Date("2026-04-12T09:00:00Z") }),
        entry({
          kind: "photo",
          transcript: null,
          capturedAt: new Date("2026-04-13T09:00:00Z"),
          photoUrl: "https://cdn.example.test/jour-2.jpg",
        }),
      ],
    });

    const days = payload["days"] as Record<string, unknown>[];
    expect(days[0]?.["photos"]).toBeUndefined();
    expect(days[1]?.["photos"]).toEqual(["https://cdn.example.test/jour-2.jpg"]);
  });

  it("échappe le HTML présent dans une transcription", async () => {
    const payload = await structurer.structure({
      title: "Carnet",
      subtitle: null,
      authors: null,
      theme: null,
      coverPhotoUrl: null,
      entries: [entry({ transcript: "On a vu un <script>alert(1)</script> panneau." })],
    });

    const days = payload["days"] as Record<string, unknown>[];
    expect(days[0]?.["body_html"]).not.toContain("<script>");
    expect(days[0]?.["body_html"]).toContain("&lt;script&gt;");
  });
});
