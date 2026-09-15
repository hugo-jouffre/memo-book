import { describe, expect, it } from "vitest";
import { isDatabaseUnavailable, splitPoolBudget, withConnectionLimit } from "./databasePool.js";

describe("splitPoolBudget", () => {
  it("laisse deux connexions à pg-boss et le reste à Prisma", () => {
    expect(splitPoolBudget(5)).toEqual({ prisma: 3, boss: 2 });
  });

  it("garde au moins une connexion à chacun sur un budget minuscule", () => {
    expect(splitPoolBudget(2)).toEqual({ prisma: 1, boss: 1 });
    expect(splitPoolBudget(1)).toEqual({ prisma: 1, boss: 1 });
  });
});

describe("withConnectionLimit", () => {
  const base = "postgresql://user:pw@host.pooler.supabase.com:5432/postgres";

  it("ajoute le plafond quand l'URL n'en porte pas", () => {
    expect(withConnectionLimit(base, 3)).toBe(`${base}?connection_limit=3`);
  });

  it("respecte un plafond déjà présent dans l'URL", () => {
    expect(withConnectionLimit(`${base}?connection_limit=9`, 3)).toBe(
      `${base}?connection_limit=9`,
    );
  });

  it("conserve les autres paramètres, comme le schéma de test", () => {
    expect(withConnectionLimit(`${base}?schema=memobook_test`, 3)).toBe(
      `${base}?schema=memobook_test&connection_limit=3`,
    );
  });
});

describe("isDatabaseUnavailable", () => {
  it("reconnaît le pooler Supabase saturé", () => {
    const error = new Error(
      "FATAL: (EMAXCONNSESSION) max clients reached in session mode - max clients are limited to pool_size: 15",
    );
    expect(isDatabaseUnavailable(error)).toBe(true);
  });

  it("reconnaît les codes Prisma de connexion", () => {
    for (const code of ["P1001", "P1002", "P1017", "P2024"]) {
      expect(isDatabaseUnavailable(Object.assign(new Error("x"), { code }))).toBe(true);
    }
  });

  it("reconnaît une erreur d'initialisation Prisma", () => {
    const error = new Error("Can't reach database server");
    error.name = "PrismaClientInitializationError";
    expect(isDatabaseUnavailable(error)).toBe(true);
  });

  it("laisse passer les autres erreurs", () => {
    expect(isDatabaseUnavailable(new Error("Unique constraint failed"))).toBe(false);
    expect(isDatabaseUnavailable(Object.assign(new Error("x"), { code: "P2002" }))).toBe(false);
    expect(isDatabaseUnavailable("pas une erreur")).toBe(false);
  });
});
