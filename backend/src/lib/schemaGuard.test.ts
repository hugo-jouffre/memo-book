import { describe, expect, it } from "vitest";
import { missingMigrations, SchemaGuard, shippedMigrations } from "./schemaGuard.js";

describe("shippedMigrations", () => {
  it("lit les migrations du dépôt, dans l'ordre, sans le verrou de Prisma", () => {
    const shipped = shippedMigrations();

    expect(shipped[0]).toBe("20260808124433_init");
    expect(shipped).toContain("20260928120000_contexte_du_voyage");
    expect(shipped).not.toContain("migration_lock.toml");
    expect([...shipped].sort()).toEqual(shipped);
  });
});

describe("missingMigrations", () => {
  it("rend ce que le code attend et que la base n'a pas", () => {
    expect(missingMigrations(["a", "b", "c"], ["a", "c"])).toEqual(["b"]);
  });

  it("ignore une migration que la base a en plus du code", () => {
    // Une version plus ancienne du code, redéployée après une migration : son
    // schéma est un sous-ensemble de celui de la base, et elle sait tourner.
    expect(missingMigrations(["a"], ["a", "b"])).toEqual([]);
  });
});

/** Une base dont on fixe les migrations appliquées, et qui compte ses lectures. */
function fakeDatabase(applied: string[]) {
  const database = {
    applied,
    reads: 0,
    $queryRaw: async () => {
      database.reads += 1;
      return database.applied.map((migration_name) => ({ migration_name }));
    },
  };
  return database;
}

describe("SchemaGuard", () => {
  it("signale la base en retard, puis la voit rattraper le code", async () => {
    const database = fakeDatabase(["a"]);
    const guard = new SchemaGuard(database as never, () => ["a", "b"]);

    expect(await guard.pending()).toEqual(["b"]);

    database.applied = ["a", "b"];
    expect(await guard.pending()).toEqual([]);
  });

  it("ne relit plus la base une fois le schéma à jour", async () => {
    const database = fakeDatabase(["a", "b"]);
    const guard = new SchemaGuard(database as never, () => ["a", "b"]);

    await guard.pending();
    await guard.pending();

    expect(database.reads).toBe(1);
  });
});
