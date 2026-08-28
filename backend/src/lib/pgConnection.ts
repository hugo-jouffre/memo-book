import { readFileSync } from "node:fs";
import type { ConnectionOptions } from "node:tls";

/**
 * Un seul `DATABASE_URL`, deux clients qui ne parlent pas le même dialecte.
 *
 * `DATABASE_URL` est écrit dans le dialecte **Prisma** (`sslmode`, `sslcert`,
 * `sslaccept`), parce que c'est le seul que `prisma migrate deploy` sait lire :
 * la CLI prend la variable d'environnement telle quelle, aucun code du back-end
 * ne peut s'interposer.
 *
 * pg-boss, lui, passe la chaîne à node-postgres, qui attend `sslrootcert` et
 * traiterait `sslcert` comme un certificat *client* — il enverrait donc
 * l'autorité de certification au serveur en guise d'identité. Ce module fait la
 * traduction : il sort les paramètres `ssl*` de l'URL et rend à la place la
 * configuration TLS que node-postgres attend.
 *
 * L'ordre compte : node-postgres réapplique ce qu'il trouve dans la chaîne
 * *par-dessus* les options explicites (`Object.assign({}, config, parse(url))`).
 * Laisser un `ssl*` dans la chaîne écraserait silencieusement le certificat
 * qu'on vient de charger.
 */
export interface PgConnection {
  connectionString: string;
  /** Absent quand l'URL ne demande aucun TLS — le cas du Postgres local. */
  ssl?: ConnectionOptions | false;
}

/** Le `sslmode` de l'URL, ou `undefined` si elle n'en porte pas. */
export function databaseSslMode(databaseUrl: string): string | undefined {
  return parseDatabaseUrl(databaseUrl).searchParams.get("sslmode") ?? undefined;
}

export function pgConnectionFrom(databaseUrl: string): PgConnection {
  const url = parseDatabaseUrl(databaseUrl);
  const params = url.searchParams;

  const sslmode = params.get("sslmode");
  const sslaccept = params.get("sslaccept");
  // `sslcert` côté Prisma, `sslrootcert` côté libpq : les deux désignent ici
  // l'autorité de certification de l'instance managée.
  const caPath = params.get("sslcert") ?? params.get("sslrootcert");

  for (const key of [...params.keys()]) {
    if (key.startsWith("ssl")) params.delete(key);
  }

  const connectionString = url.toString();

  if (sslmode === null) {
    return { connectionString };
  }

  if (sslmode === "disable") {
    return { connectionString, ssl: false };
  }

  if (sslaccept === "accept_invalid_certs") {
    return { connectionString, ssl: { rejectUnauthorized: false } };
  }

  if (caPath === null) {
    if (sslmode === "verify-ca" || sslmode === "verify-full") {
      throw new Error(
        `DATABASE_URL demande sslmode=${sslmode} sans certificat : ajoute ` +
          "`sslcert=<chemin vers le PEM de l'autorité>` (voir docs/database.md).",
      );
    }
    // Chiffré mais non vérifié — la sémantique de `sslmode=require` chez libpq.
    return { connectionString, ssl: { rejectUnauthorized: false } };
  }

  const ca = readCertificate(caPath);

  if (sslmode === "verify-full") {
    return { connectionString, ssl: { ca, rejectUnauthorized: true } };
  }

  return {
    connectionString,
    ssl: {
      ca,
      rejectUnauthorized: true,
      // `require` et `verify-ca` vérifient la chaîne, pas le nom d'hôte. Sans
      // cette neutralisation, node-postgres irait plus loin que ce que l'URL
      // demande et refuserait une connexion par IP. Le nom d'hôte se vérifie
      // en passant explicitement `sslmode=verify-full`.
      checkServerIdentity: () => undefined,
    },
  };
}

function parseDatabaseUrl(databaseUrl: string): URL {
  try {
    return new URL(databaseUrl);
  } catch {
    throw new Error(
      "DATABASE_URL n'est pas une URL valide (attendu : postgresql://utilisateur:mot-de-passe@hôte:port/base).",
    );
  }
}

function readCertificate(path: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch {
    throw new Error(
      `Certificat introuvable ou illisible : ${path}. C'est le PEM de l'autorité ` +
        "de l'instance managée, déposé par scripts/provision-db-scaleway.sh.",
    );
  }
}
