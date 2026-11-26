import { describe, expect, it } from "vitest";
import { testDatabaseUrl } from "./helpers.js";

/**
 * **La suite ne doit jamais vider la base de développement.**
 *
 * Elle l'a fait deux fois : le 19/11/2026, et le 26/11/2026 où trois passages
 * ont effacé un compte et son carnet, irrécupérables. À chaque fois la cause
 * était la même — `TEST_DATABASE_URL` absent de `backend/.env`, et un repli sur
 * `DATABASE_URL` que seul un commentaire déconseillait.
 *
 * Ces tests-ci tiennent la garde qui a remplacé le commentaire.
 */

const DEV = "postgresql://memobook:memobook@localhost:5432/memobook";

describe("la base que la suite vide", () => {
  it("dérive une base à elle quand personne ne la nomme", () => {
    expect(testDatabaseUrl(undefined, DEV)).toBe(
      "postgresql://memobook:memobook@localhost:5432/memobook_test",
    );
  });

  it("garde les paramètres de connexion en la dérivant", () => {
    expect(testDatabaseUrl(undefined, `${DEV}?connection_limit=5`)).toBe(
      "postgresql://memobook:memobook@localhost:5432/memobook_test?connection_limit=5",
    );
  });

  it("prend celle qu'on lui nomme", () => {
    const ailleurs = "postgresql://memobook:memobook@localhost:5432/essais";
    expect(testDatabaseUrl(ailleurs, DEV)).toBe(ailleurs);
  });

  it("refuse la base de développement, même nommée exprès", () => {
    // Le cas qui a coûté un carnet : la suite part, et vide.
    expect(() => testDatabaseUrl(DEV, DEV)).toThrow(/même base/);
  });

  it("refuse une base de dev déguisée par ses paramètres", () => {
    expect(() => testDatabaseUrl(`${DEV}?connection_limit=1`, DEV)).toThrow(/même base/);
  });

  it("ne redérive pas une base déjà suffixée", () => {
    const deja = `${DEV}_test`;
    expect(testDatabaseUrl(undefined, deja)).toBe(deja);
  });

  it("se rabat sur une base de test nommée quand il n'y a pas de DATABASE_URL", () => {
    expect(testDatabaseUrl(undefined, undefined)).toMatch(/_test$/);
  });
});
