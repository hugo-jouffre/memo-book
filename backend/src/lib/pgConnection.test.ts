import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { databaseSslMode, pgConnectionFrom } from "./pgConnection.js";

const dir = mkdtempSync(join(tmpdir(), "memobook-pg-"));
const caPath = join(dir, "ca.pem");
const CA = "-----BEGIN CERTIFICATE-----\nfaux\n-----END CERTIFICATE-----\n";
writeFileSync(caPath, CA);

afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

const managed = (extra = ""): string =>
  `postgresql://memobook:secret@rw-abc.rdb.fr-par.scw.cloud:12345/memobook?sslmode=require&sslcert=${caPath}&sslaccept=strict${extra}`;

/**
 * Ce qui se joue ici : `DATABASE_URL` est écrit pour Prisma, et node-postgres
 * lirait `sslcert` comme un certificat *client*. Une traduction ratée ne casse
 * rien en local — le Postgres de docker-compose est en clair — et ne se voit
 * qu'au premier démarrage contre la base managée.
 */
describe("pgConnectionFrom", () => {
  it("laisse l'URL locale intacte, sans TLS", () => {
    const url = "postgresql://memobook:memobook@localhost:5432/memobook";

    expect(pgConnectionFrom(url)).toEqual({ connectionString: url });
  });

  it("charge l'autorité et sort les paramètres ssl* de la chaîne", () => {
    const connection = pgConnectionFrom(managed("&connection_limit=10"));

    expect(connection.connectionString).toBe(
      "postgresql://memobook:secret@rw-abc.rdb.fr-par.scw.cloud:12345/memobook?connection_limit=10",
    );
    // Sinon node-postgres réappliquerait la chaîne par-dessus ces options.
    expect(connection.connectionString).not.toContain("ssl");
    expect(connection.ssl).toMatchObject({ ca: CA, rejectUnauthorized: true });
  });

  it("accepte `sslrootcert`, le nom libpq du même fichier", () => {
    const connection = pgConnectionFrom(
      `postgresql://a:b@h:5432/d?sslmode=require&sslrootcert=${caPath}`,
    );

    expect(connection.ssl).toMatchObject({ ca: CA });
  });

  it("ne vérifie le nom d'hôte que sur sslmode=verify-full", () => {
    const requireMode = pgConnectionFrom(managed());
    const verifyFull = pgConnectionFrom(
      `postgresql://a:b@h:5432/d?sslmode=verify-full&sslcert=${caPath}`,
    );

    expect(requireMode.ssl).toHaveProperty("checkServerIdentity");
    expect(verifyFull.ssl).not.toHaveProperty("checkServerIdentity");
  });

  it("chiffre sans vérifier quand aucune autorité n'est fournie", () => {
    const connection = pgConnectionFrom("postgresql://a:b@h:5432/d?sslmode=require");

    expect(connection.ssl).toEqual({ rejectUnauthorized: false });
  });

  it("coupe TLS sur sslmode=disable", () => {
    expect(pgConnectionFrom("postgresql://a:b@h:5432/d?sslmode=disable").ssl).toBe(false);
  });

  it("refuse verify-full sans certificat plutôt que de dégrader la vérification", () => {
    expect(() => pgConnectionFrom("postgresql://a:b@h:5432/d?sslmode=verify-full")).toThrow(
      /sslcert/,
    );
  });

  it("nomme le certificat manquant", () => {
    expect(() =>
      pgConnectionFrom("postgresql://a:b@h:5432/d?sslmode=require&sslcert=/introuvable.pem"),
    ).toThrow(/introuvable\.pem/);
  });
});

describe("databaseSslMode", () => {
  it("lit le mode demandé, ou rien", () => {
    expect(databaseSslMode(managed())).toBe("require");
    expect(databaseSslMode("postgresql://a:b@h:5432/d")).toBeUndefined();
  });
});
