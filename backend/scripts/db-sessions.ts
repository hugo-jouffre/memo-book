/**
 * Qui tient les connexions de la base — et, au besoin, coupe celles que plus
 * personne ne tient.
 *
 *   npm run db:sessions           liste, ne touche à rien
 *   npm run db:sessions -- --reap ferme les sessions inactives depuis 30 min
 *   npm run db:sessions -- --reap --minutes 60
 *
 * **Pourquoi ce script existe.** Le pooler Supabase, en mode session
 * (port 5432), n'accorde que **15 clients au total** — pour tout ce qui parle à
 * cette base, l'API déployée comprise. Un serveur de développement en prend
 * huit à lui seul : quatre pour Prisma, quatre pour pg-boss. Quand il n'en
 * reste plus, tout échoue d'un coup et **rien ne dit pourquoi** : les routes
 * répondent « Erreur interne du serveur », et la cause est deux étages plus
 * bas. On a déjà perdu une matinée dessus.
 *
 * `--reap` ne ferme que des sessions **inactives** depuis un long moment : un
 * client vivant touche la sienne bien plus souvent — pg-boss interroge sa file
 * toutes les quelques secondes. Fermer une session inactive n'est de toute
 * façon pas destructeur : rien n'est en cours dessus, et Prisma comme pg-boss
 * se reconnectent d'eux-mêmes.
 *
 * ⚠️ La base est **partagée avec la production**. Le script le rappelle avant
 * de couper quoi que ce soit, et n'y touche jamais sans `--reap`.
 */

import { Client } from "pg";
import { loadEnv } from "../src/env.js";

const REAP = process.argv.includes("--reap");
const MINUTES = (() => {
  const at = process.argv.indexOf("--minutes");
  const value = at === -1 ? NaN : Number(process.argv[at + 1]);
  return Number.isFinite(value) && value > 0 ? value : 30;
})();

/** Ce que le pooler Supabase accorde en mode session. */
const SESSION_MODE_LIMIT = 15;

/**
 * Le nom sous lequel le pooler se présente. Ce sont **ces** sessions-là qui
 * comptent dans la limite, et les seules que le script accepte de fermer : les
 * autres appartiennent à Supabase — PostgREST, `pg_cron`, `pg_net`, la sonde de
 * métriques — et couper un service de l'hébergeur n'est pas notre affaire.
 */
const POOLER = "Supavisor";

interface Session {
  pid: number;
  application_name: string;
  state: string | null;
  inactifMinutes: number | null;
  requete: string;
}

/**
 * Une connexion à nous, hors pool : le script doit pouvoir parler à la base
 * **au moment précis** où elle n'en accorde plus, et un `PrismaClient` en
 * prendrait quatre pour poser une question.
 */
function directClient(databaseUrl: string): Client {
  const url = new URL(databaseUrl);
  url.searchParams.delete("connection_limit");
  url.searchParams.delete("pool_timeout");
  return new Client({ connectionString: url.toString() });
}

function describe(session: Session): string {
  const query = session.requete.replace(/\s+/g, " ").trim().slice(0, 52) || "—";
  const age = session.inactifMinutes === null ? "—" : `${Math.round(session.inactifMinutes)} min`;
  const who = (session.application_name || "?").slice(0, 20);
  return [
    `  ${String(session.pid).padEnd(9)}`,
    who.padEnd(21),
    (session.state ?? "—").padEnd(8),
    age.padStart(8),
    ` ${query}`,
  ].join(" ");
}

async function main(): Promise<void> {
  const env = loadEnv();
  const client = directClient(env.DATABASE_URL);

  try {
    await client.connect();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`\nImpossible d'ouvrir une seule connexion : ${message}\n`);
    console.error(
      "Le pooler est saturé au point de ne plus laisser passer ce script.\n" +
        "Arrête le serveur de développement, un `prisma studio`, ou toute autre\n" +
        "commande qui parle à la base, puis relance.\n",
    );
    process.exitCode = 1;
    return;
  }

  try {
    const { rows } = await client.query<Session>(
      `SELECT pid,
              COALESCE(application_name, '') AS application_name,
              state,
              (EXTRACT(EPOCH FROM (now() - state_change)) / 60)::float8 AS "inactifMinutes",
              COALESCE(query, '') AS requete
         FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid <> pg_backend_pid()
        ORDER BY state_change NULLS FIRST`,
    );

    const throughPooler = rows.filter((session) => session.application_name.startsWith(POOLER));

    console.log(
      `\n${rows.length} sessions ouvertes, dont ${throughPooler.length} par le pooler ` +
        `(limite du mode session : ${SESSION_MODE_LIMIT}).\n`,
    );
    console.log("  PID       QUI                   ÉTAT      INACTIF  DERNIÈRE REQUÊTE");
    for (const session of rows) console.log(describe(session));

    const dead = throughPooler.filter(
      (session) => session.state === "idle" && (session.inactifMinutes ?? 0) >= MINUTES,
    );

    console.log(`\n${dead.length} sessions du pooler inactives depuis plus de ${MINUTES} min.`);

    if (!REAP) {
      console.log(dead.length > 0 ? "Pour les fermer : npm run db:sessions -- --reap\n" : "");
      return;
    }

    console.log("⚠️  Cette base est partagée avec la production — on ne ferme que l'inactif.\n");

    let closed = 0;
    for (const session of dead) {
      const { rows: result } = await client.query<{ pg_terminate_backend: boolean }>(
        "SELECT pg_terminate_backend($1)",
        [session.pid],
      );
      if (result[0]?.pg_terminate_backend) closed += 1;
    }

    console.log(
      `${closed} sessions fermées, ${SESSION_MODE_LIMIT - (throughPooler.length - closed)} places libres.\n`,
    );
  } finally {
    await client.end().catch(() => {});
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
