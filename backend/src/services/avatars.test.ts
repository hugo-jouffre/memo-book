import { describe, expect, it } from "vitest";
import { publicApiBaseUrl } from "./avatars.js";

describe("la racine publique de l'API", () => {
  it("prend la variable posée à la main avant tout", () => {
    expect(
      publicApiBaseUrl({
        API_PUBLIC_BASE_URL: "https://api.memo-book.com/",
        RAILWAY_PUBLIC_DOMAIN: "api-production-9f35a.up.railway.app",
        APP_LINK_BASE_URL: "memobook://",
      }),
    ).toBe("https://api.memo-book.com");
  });

  it("se sert du domaine que Railway pose sur le service, sans rien configurer", () => {
    expect(
      publicApiBaseUrl({
        API_PUBLIC_BASE_URL: "",
        RAILWAY_PUBLIC_DOMAIN: "api-production-9f35a.up.railway.app",
        APP_LINK_BASE_URL: "memobook://",
      }),
    ).toBe("https://api-production-9f35a.up.railway.app");
  });

  it("retombe sur l'adresse de l'API quand c'est celle des liens d'e-mail, puis sur la boucle locale", () => {
    expect(
      publicApiBaseUrl({
        API_PUBLIC_BASE_URL: "",
        RAILWAY_PUBLIC_DOMAIN: "",
        APP_LINK_BASE_URL: "https://api.memo-book.com/",
      }),
    ).toBe("https://api.memo-book.com");
    expect(
      publicApiBaseUrl({ API_PUBLIC_BASE_URL: "", RAILWAY_PUBLIC_DOMAIN: "", APP_LINK_BASE_URL: "memobook://" }),
    ).toBe("http://localhost:3000");
  });
});
