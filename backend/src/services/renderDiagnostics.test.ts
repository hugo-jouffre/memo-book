import { describe, expect, it } from "vitest";
import { photosDiagnostic } from "./renderDiagnostics.js";

/**
 * Les trois façons de sortir un carnet sans photos, et la seule configuration
 * qui n'en est pas une. Voir `services/renderDiagnostics.ts`.
 */

type Env = Parameters<typeof photosDiagnostic>[0];

/** La production telle qu'on la veut : moteur réel, adresse posée à la main. */
function production(overrides: Partial<Env> = {}): Env {
  return {
    API_PUBLIC_BASE_URL: "https://api-production.up.railway.app",
    RAILWAY_PUBLIC_DOMAIN: "",
    APP_LINK_BASE_URL: "https://api-production.up.railway.app",
    NODE_ENV: "production",
    RENDERER: "auto",
    APITEMPLATE_API_KEY: "cle",
    live: true,
    ...overrides,
  };
}

describe("le diagnostic des photos du carnet", () => {
  it("ne reproche rien à une production correctement posée", () => {
    const diagnostic = photosDiagnostic(production());

    expect(diagnostic.renderer).toBe("apitemplate");
    expect(diagnostic.photoBaseUrlFrom).toBe("API_PUBLIC_BASE_URL");
    expect(diagnostic.problems).toEqual([]);
  });

  it("dit que le moteur est simulé quand la clé manque", () => {
    const diagnostic = photosDiagnostic(production({ APITEMPLATE_API_KEY: "" }));

    expect(diagnostic.renderer).toBe("fake");
    expect(diagnostic.problems.join(" ")).toContain("simulé");
  });

  it("dit la boucle locale, qui est le cas du worker sans variable", () => {
    // Ni `API_PUBLIC_BASE_URL`, ni domaine Railway — un worker n'en a pas —,
    // et un `APP_LINK_BASE_URL` qui n'est pas une adresse web.
    const diagnostic = photosDiagnostic(
      production({ API_PUBLIC_BASE_URL: "", APP_LINK_BASE_URL: "memobook://" }),
    );

    expect(diagnostic.photoBaseUrl).toBe("http://localhost:3000");
    expect(diagnostic.problems.join(" ")).toContain("API_PUBLIC_BASE_URL");
  });

  it("signale l'adresse juste obtenue par un repli", () => {
    const diagnostic = photosDiagnostic(production({ API_PUBLIC_BASE_URL: "" }));

    expect(diagnostic.photoBaseUrlFrom).toBe("APP_LINK_BASE_URL");
    expect(diagnostic.problems.join(" ")).toContain("rien ne la tient");
  });

  it("attrape l'adresse posée sans son protocole, et la répare", () => {
    // La vraie valeur posée en production le 13/11/2026, après la panne de
    // `sharp` : la variable était là, et les cadres restaient vides.
    const diagnostic = photosDiagnostic(
      production({ API_PUBLIC_BASE_URL: "api-production-9f35a.up.railway.app" }),
    );

    expect(diagnostic.photoBaseUrl).toBe("https://api-production-9f35a.up.railway.app");
    expect(diagnostic.problems.join(" ")).toContain("ne porte pas son protocole");
  });

  it("le reproche même en rendu local : c'est la variable qui est fautive", () => {
    const diagnostic = photosDiagnostic(
      production({ RENDERER: "local", API_PUBLIC_BASE_URL: "api.exemple.fr" }),
    );

    expect(diagnostic.problems).toHaveLength(1);
  });

  it("laisse tranquille le rendu local, qui compose sur place", () => {
    const diagnostic = photosDiagnostic(
      production({ NODE_ENV: "development", RENDERER: "local", API_PUBLIC_BASE_URL: "" , APP_LINK_BASE_URL: "memobook://" }),
    );

    expect(diagnostic.renderer).toBe("local");
    expect(diagnostic.problems).toEqual([]);
  });
});
