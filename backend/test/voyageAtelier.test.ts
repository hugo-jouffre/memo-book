import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";

/**
 * Le voyage tel que les récits le racontent (`MemoBook Generator/public/voyage.js`) :
 * l'itinéraire, les moyens de transport, et les chiffres de la quatrième de
 * couverture — kilomètres, pays, villes.
 */
const require = createRequire(import.meta.url);
type Lieu = { nom: string; pays: string; lat: number; lon: number; genre?: string };
const V = require("../../MemoBook Generator/public/voyage.js") as {
  modeDe: (v: unknown) => string | null;
  distanceKm: (a: Lieu, b: Lieu) => number;
  itineraire: (etapes: unknown[]) => (Lieu & { mode: string | null; revisite: boolean })[];
  lieuxDeSejour: (etapes: unknown[]) => (Lieu & { mode: string | null })[];
  chiffresDuVoyage: (etapes: unknown[]) => { km: number | null; pays: string[]; villes: string[] };
  nombreCourt: (n: number | null) => string;
};

const lieu = (nom: string, pays: string, lat: number, lon: number, genre?: string): Lieu => ({
  nom,
  pays,
  lat,
  lon,
  ...(genre ? { genre } : {}),
});
const geneve = lieu("Genève", "CH", 46.2, 6.14);
const mykonos = lieu("Mykonos", "GR", 37.45, 25.33);
const paros = lieu("Paros", "GR", 37.08, 25.15);
const naoussa = lieu("Naoussa", "GR", 37.123, 25.238, "ville");
const naxos = lieu("Naxos", "GR", 37.1, 25.38);
const trajet = (depart: Lieu, arrivee: Lieu, mode: string) => ({ depart, arrivee, mode });

const etapes = [
  {
    analyse: {
      lieu: { ...paros, genre: "site" },
      lieux: [naoussa],
      trajets: [trajet(geneve, mykonos, "avion"), trajet(mykonos, paros, "ferry")],
    },
  },
  { analyse: { lieu: { ...naxos, genre: "site" }, lieux: [], trajets: [trajet(paros, naxos, "bateau")] } },
  {
    analyse: {
      lieu: { ...mykonos, genre: "site" },
      lieux: [lieu("Chora", "GR", 37.446, 25.328, "ville")],
      trajets: [trajet(naxos, mykonos, "bateau"), trajet(mykonos, geneve, "avion")],
    },
  },
];

describe("le voyage raconté", () => {
  it("ramène chaque moyen de transport à une façon de le dessiner", () => {
    expect(V.modeDe("ferry")).toBe("bateau");
    expect(V.modeDe("Vol")).toBe("avion");
    expect(V.modeDe("scooter")).toBe("terre");
    expect(V.modeDe("à pied")).toBe("terre");
    expect(V.modeDe("téléportation")).toBeNull();
  });

  it("mesure les distances à vol d'oiseau", () => {
    // Paris – Londres : 344 km.
    expect(V.distanceKm(lieu("Paris", "FR", 48.8566, 2.3522), lieu("Londres", "GB", 51.5074, -0.1278))).toBeCloseTo(344, -1);
  });

  it("met les lieux dans l'ordre de visite, sans la maison, avec le moyen d'y arriver", () => {
    const ordre = V.itineraire(etapes);
    expect(ordre.map((l) => l.nom)).toEqual(["Mykonos", "Paros", "Naoussa", "Naxos", "Mykonos", "Chora"]);
    expect(ordre.map((l) => l.mode)).toEqual(["avion", "bateau", null, "bateau", "bateau", null]);
    expect(ordre[4]!.revisite).toBe(true);
  });

  it("ne garde, pour la carte de quatrième, que les villes ou les îles où le voyage a séjourné", () => {
    const sejours = V.lieuxDeSejour(etapes);
    // Ni Naoussa ni Chora (visités en chemin), ni la maison.
    expect(sejours.map((l) => l.nom)).toEqual(["Paros", "Naxos", "Mykonos"]);
    expect(sejours.map((l) => l.mode)).toEqual(["bateau", "bateau", "bateau"]);
  });

  it("compte les kilomètres des trajets racontés, et distingue pays et villes", () => {
    const c = V.chiffresDuVoyage(etapes);
    // Deux vols Genève – Mykonos (~1 840 km chacun) et trois traversées (~100 km).
    expect(c.km).toBeGreaterThan(3750);
    expect(c.km).toBeLessThan(3900);
    // La Suisse est la maison, pas un pays visité ; une île n'est pas une ville.
    expect(c.pays).toEqual(["GR"]);
    expect(c.villes).toEqual(["Naoussa", "Chora"]);
  });

  it("compte la route 1,3 fois le vol d'oiseau", () => {
    const a = lieu("Lyon", "FR", 45.764, 4.8357, "ville");
    const b = lieu("Marseille", "FR", 43.2965, 5.3698, "ville");
    const c = V.chiffresDuVoyage([{ analyse: { lieu: b, lieux: [], trajets: [trajet(a, b, "train")] } }]);
    expect(c.km).toBe(Math.round(V.distanceKm(a, b) * 1.3));
  });

  it("ne compte pas de kilomètres quand le récit ne raconte aucun trajet", () => {
    expect(V.chiffresDuVoyage([{ analyse: { lieu: paros, lieux: [] } }]).km).toBeNull();
  });

  it("écrit les grands nombres comme la quatrième", () => {
    expect(V.nombreCourt(22340)).toBe("22k");
    expect(V.nombreCourt(3900).replace(/\s/g, " ")).toBe("3 900");
    expect(V.nombreCourt(null)).toBe("—");
  });
});
