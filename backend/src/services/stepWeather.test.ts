import { describe, expect, it } from "vitest";
import { lookupDayOf, lookupPlaceOf, stepWeatherOf } from "./stepWeather.js";

describe("le temps qu'il faisait à une étape", () => {
  it("prend l'icône du premier souvenir qui a parlé du temps", () => {
    const step = {
      entries: [{ weatherKey: null }, { weatherKey: "rain" }, { weatherKey: "sun" }],
    };
    // Le premier, et non le plus fréquent : les souvenirs sont dans l'ordre du
    // récit, et c'est celui-là qui plante le décor. Même règle que le carnet.
    expect(stepWeatherOf(step).weatherKey).toBe("rain");
  });

  it("n'invente pas d'icône quand personne n'a dit le temps", () => {
    expect(stepWeatherOf({ entries: [{ weatherKey: null }] }).weatherKey).toBeNull();
    expect(stepWeatherOf({ entries: [] }).weatherKey).toBeNull();
    expect(stepWeatherOf({}).weatherKey).toBeNull();
  });

  it("écarte une clé que le gabarit ne saurait pas dessiner", () => {
    // Un modèle qui rendrait « brouillard » ne doit pas faire chercher une
    // image qui n'existe pas.
    expect(stepWeatherOf({ entries: [{ weatherKey: "brouillard" }] }).weatherKey).toBeNull();
  });

  /**
   * **Le test qui porte la décision du ticket.** Une température dite est un
   * souvenir ; une température relevée est une donnée. Quand les deux
   * existent, c'est le souvenir qui s'affiche, même s'il est faux.
   */
  it("fait passer la température dite avant celle qu'on a cherchée", () => {
    const step = { temperatureC: 18, entries: [{ temperatureC: 30 }] };
    expect(stepWeatherOf(step)).toMatchObject({ temperatureC: 30, temperatureSource: "told" });
  });

  it("retombe sur celle qu'on a cherchée quand personne ne l'a dite", () => {
    const step = { temperatureC: 18, entries: [{ temperatureC: null }, {}] };
    expect(stepWeatherOf(step)).toMatchObject({ temperatureC: 18, temperatureSource: "looked-up" });
  });

  it("n'affiche rien quand ni l'un ni l'autre n'existe", () => {
    expect(stepWeatherOf({ entries: [{}] })).toMatchObject({
      temperatureC: null,
      temperatureSource: null,
    });
  });

  it("garde les températures négatives, qui sont des températures comme les autres", () => {
    expect(stepWeatherOf({ entries: [{ temperatureC: -12 }] }).temperatureC).toBe(-12);
    // Et zéro n'est pas « rien » : un `||` l'aurait avalé.
    expect(stepWeatherOf({ entries: [{ temperatureC: 0 }] })).toMatchObject({
      temperatureC: 0,
      temperatureSource: "told",
    });
  });
});

describe("ce qu'on donne au service météo", () => {
  it("nomme la ville avec son pays, pour lever les homonymes", () => {
    expect(
      lookupPlaceOf({ destinationName: "Cebu", destinationCountryCode: "PH" }),
    ).toBe("Cebu, PH");
  });

  it("retombe sur le libellé libre quand il n'y a pas de destination", () => {
    expect(lookupPlaceOf({ placeName: "Trastevere", destinationCountryCode: "IT" })).toBe(
      "Trastevere, IT",
    );
  });

  it("ne demande rien quand il n'y a aucun lieu", () => {
    expect(lookupPlaceOf({})).toBeNull();
    expect(lookupPlaceOf({ destinationName: "   " })).toBeNull();
  });

  it("interroge le jour où l'étape commence, pas une moyenne de la semaine", () => {
    const debut = new Date("2026-02-23T00:00:00Z");
    const fin = new Date("2026-03-02T00:00:00Z");
    expect(lookupDayOf({ startDate: debut, endDate: fin })).toBe(debut);
    expect(lookupDayOf({ startDate: null, endDate: fin })).toBe(fin);
    expect(lookupDayOf({})).toBeNull();
  });
});
