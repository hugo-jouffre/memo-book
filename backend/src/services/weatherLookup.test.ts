import { describe, expect, it, vi } from "vitest";
import { isoDay, lookUpTemperature } from "./weatherLookup.js";

const env = {
  VISUAL_CROSSING_URL: "https://meteo.test/timeline",
  VISUAL_CROSSING_API_KEY: "cle-de-test",
} as const;

function reponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response;
}

const jour = new Date("2026-08-02T12:00:00Z");

describe("relever une température", () => {
  it("demande le bon jour, en Celsius, et ne tire que ce chiffre", async () => {
    const fetcher = vi.fn().mockResolvedValue(reponse({ days: [{ temp: 28.6 }] }));

    const t = await lookUpTemperature({ env, fetcher }, "Tokyo, JP", jour);

    expect(t).toBe(29);
    const url = new URL(String(fetcher.mock.calls[0]![0]));
    // Le nom du lieu part tel quel : c'est le service qui le place sur la
    // carte, et c'est ce qui nous épargne un géocodeur.
    expect(decodeURIComponent(url.pathname)).toBe("/timeline/Tokyo, JP/2026-08-02");
    expect(url.searchParams.get("unitGroup")).toBe("metric");
    expect(url.searchParams.get("elements")).toBe("temp");
    expect(url.searchParams.get("key")).toBe("cle-de-test");
  });

  /**
   * **Le test qui compte.** Cet appel est sur le chemin d'une rédaction qui
   * vient de réussir. Rien de ce qui suit ne doit jeter : au pire l'étape
   * n'affiche pas de température, et personne ne le remarque.
   */
  it("ne jette jamais, quoi que fasse le service", async () => {
    const cas: [string, typeof fetch][] = [
      ["réseau coupé", vi.fn().mockRejectedValue(new Error("ECONNRESET")) as never],
      ["lieu introuvable", vi.fn().mockResolvedValue(reponse({}, 400)) as never],
      ["quota dépassé", vi.fn().mockResolvedValue(reponse({}, 429)) as never],
      ["réponse illisible", vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => {
          throw new Error("pas du JSON");
        },
      }) as never],
      ["aucun jour", vi.fn().mockResolvedValue(reponse({ days: [] })) as never],
      ["jour sans température", vi.fn().mockResolvedValue(reponse({ days: [{}] })) as never],
      ["température illisible", vi.fn().mockResolvedValue(reponse({ days: [{ temp: "chaud" }] })) as never],
    ];

    for (const [nom, fetcher] of cas) {
      const warn = vi.fn();
      await expect(
        lookUpTemperature({ env, fetcher, warn }, "Tokyo, JP", jour),
        nom,
      ).resolves.toBeNull();
    }
  });

  it("écarte un chiffre hors du plausible plutôt que de l'afficher", async () => {
    // 84 °F servis comme des Celsius, par exemple : un service qui change
    // d'unité sans le dire est plus probable qu'un 84 vécu par quelqu'un.
    const fetcher = vi.fn().mockResolvedValue(reponse({ days: [{ temp: 84 }] }));
    const warn = vi.fn();

    await expect(lookUpTemperature({ env, fetcher, warn }, "Tokyo, JP", jour)).resolves.toBeNull();
    expect(warn).toHaveBeenCalled();
  });

  it("garde le froid, qui est plausible", async () => {
    const fetcher = vi.fn().mockResolvedValue(reponse({ days: [{ temp: -41.2 }] }));
    await expect(lookUpTemperature({ env, fetcher }, "Oymyakon, RU", jour)).resolves.toBe(-41);
  });

  it("n'appelle rien sans clé, et rien sans lieu", async () => {
    const fetcher = vi.fn();

    await expect(
      lookUpTemperature({ env: { ...env, VISUAL_CROSSING_API_KEY: undefined }, fetcher }, "Tokyo", jour),
    ).resolves.toBeNull();
    await expect(lookUpTemperature({ env, fetcher }, "   ", jour)).resolves.toBeNull();

    expect(fetcher).not.toHaveBeenCalled();
  });

  it("date le jour en UTC, sans décalage d'un jour", () => {
    expect(isoDay(new Date("2026-08-02T23:30:00Z"))).toBe("2026-08-02");
    expect(isoDay(new Date("2026-01-01T00:00:00Z"))).toBe("2026-01-01");
  });
});
