import { afterAll, beforeAll, describe, expect, it } from "vitest";
import pino from "pino";
import { buildApp } from "../src/app.js";
import { createContext } from "../src/context.js";
import { testEnv } from "./helpers.js";
import type { FastifyInstance } from "fastify";

/**
 * **Le beau lien** (Hugo, 10/11/2026) — « on devrait maintenant avoir un beau
 * lien comme join.memo-book.com ».
 *
 * Sur ce domaine-là, le code d'accès se pose à la racine. Ce qui se vérifie
 * ici n'est pas la page — elle existait déjà sous `/j/<code>` — mais les deux
 * gardes qui la protègent : **l'hôte** et **la forme du code**. La même route
 * ouverte à tout va avalerait les autres pages de l'API.
 */

let app: FastifyInstance;

beforeAll(async () => {
  const context = createContext(
    { ...testEnv(), INVITE_PUBLIC_BASE_URL: "https://join.memo-book.com" },
    { overrides: { logger: pino({ level: "silent" }) } },
  );
  app = await buildApp(context);
  await app.ready();
});

afterAll(async () => {
  await app.close();
});

const surLeDomaine = (url: string) => app.inject({ method: "GET", url, headers: { host: "join.memo-book.com" } });

describe("le code à la racine du domaine des invitations", () => {
  it("sert la page d'invitation", async () => {
    const reponse = await surLeDomaine("/JHKFDA");
    expect(reponse.statusCode).toBe(200);
    expect(reponse.headers["content-type"]).toContain("text/html");
    expect(reponse.body).toContain("JHKFDA");
  });

  it("accepte un code recopié avec un tiret ou en minuscules", async () => {
    for (const forme of ["/jhk-fda", "/JHK-FDA"]) {
      const reponse = await surLeDomaine(forme);
      expect(reponse.statusCode, forme).toBe(200);
      // La page montre toujours le code dans la forme de la base.
      expect(reponse.body, forme).toContain("JHKFDA");
    }
  });

  it("garde l'ancienne forme, pour les liens déjà partis", async () => {
    const reponse = await surLeDomaine("/j/JHKFDA");
    expect(reponse.statusCode).toBe(200);
  });

  /** Un chemin d'un segment qui n'a pas la forme d'un code n'est pas une invitation. */
  it("ne répond pas à ce qui n'est pas un code", async () => {
    for (const chemin of ["/bonjour-tout-le-monde", "/ABC", "/JHKFDA/encore"]) {
      expect((await surLeDomaine(chemin)).statusCode, chemin).toBe(404);
    }
  });

  /** Et surtout : les pages de l'API ne deviennent pas des invitations. */
  it("laisse passer les routes de l'API, qui ont leur propre réponse", async () => {
    const sante = await surLeDomaine("/health");
    expect(sante.statusCode).toBe(200);
    expect(sante.body).not.toContain("Rejoins");
  });

  it("ne sert rien à la racine d'un autre hôte", async () => {
    const ailleurs = await app.inject({
      method: "GET",
      url: "/JHKFDA",
      headers: { host: "api-production-9f35a.up.railway.app" },
    });
    expect(ailleurs.statusCode).toBe(404);
  });

  /**
   * ⚠️ Le fichier qu'Apple lit **dépend de l'hôte** : `/*` sur le domaine des
   * invitations, `/j/*` ailleurs. Sans ça, l'app intercepterait `/c/<jeton>`,
   * l'aperçu public d'un carnet partagé.
   */
  it("ne revendique tout le domaine qu'ici", async () => {
    interface Aasa {
      applinks: { details: { components: Record<string, string>[] }[] };
    }
    const motif = (reponse: { json: <T>() => T }) =>
      reponse.json<Aasa>().applinks.details[0]!.components[0]!["/"];

    expect(motif(await surLeDomaine("/.well-known/apple-app-site-association"))).toBe("/*");
    expect(
      motif(
        await app.inject({
          method: "GET",
          url: "/.well-known/apple-app-site-association",
          headers: { host: "api-production-9f35a.up.railway.app" },
        }),
      ),
    ).toBe("/j/*");
  });
});
