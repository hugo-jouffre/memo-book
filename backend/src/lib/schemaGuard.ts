import { readdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { PrismaClient } from "@prisma/client";

const here = dirname(fileURLToPath(import.meta.url));

/**
 * Les migrations que l'image embarque : `backend/prisma/migrations/`, copié
 * tel quel dans l'image d'exécution (`COPY backend/prisma ./prisma`). Depuis
 * `dist/lib/` comme depuis `src/lib/`, c'est deux crans plus haut.
 */
export const MIGRATIONS_DIR = resolve(here, "../../prisma/migrations");

/** Les noms des migrations livrées avec ce code, dans l'ordre où Prisma les applique. */
export function shippedMigrations(directory: string = MIGRATIONS_DIR): string[] {
  return readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && existsSync(join(directory, entry.name, "migration.sql")))
    .map((entry) => entry.name)
    .sort();
}

/**
 * Ce que le code attend et que la base n'a pas : les migrations livrées que
 * `_prisma_migrations` ne connaît pas comme terminées.
 */
export function missingMigrations(shipped: string[], applied: Iterable<string>): string[] {
  const done = new Set(applied);
  return shipped.filter((name) => !done.has(name));
}

/**
 * **Le code ne part pas en production avant son schéma.**
 *
 * Railway lance `prisma migrate deploy` avant chaque déploiement — à condition
 * que la commande soit réglée sur le service. Le 01/10/2026, elle ne l'était
 * pas : `railway.json` la déclarait, mais Railway ne lit plus ce fichier pour
 * nos services (la « Config as Code » est dépréciée, et un service qui ne
 * l'utilisait pas déjà ne peut plus y entrer). Le code de la PR #56 est parti
 * sans sa colonne `memos.tripContext`, et l'accueil a rendu 500. C'était la
 * troisième fois (22/09, 27/09, 01/10), et chaque fois personne ne l'a su avant
 * d'ouvrir l'app.
 *
 * Ce garde-fou ne migre rien : il **refuse**. `/health` répond 503 tant qu'une
 * migration livrée manque à la base, et Railway ne bascule le trafic sur un
 * déploiement qu'une fois son contrôle de santé passé. Une commande de
 * pré-déploiement oubliée donne donc un déploiement en échec — l'ancienne
 * version reste en ligne, cohérente avec l'ancien schéma, et Railway envoie
 * son e-mail « Deploy failed » — au lieu d'une API qui rend 500.
 *
 * Une base à jour le reste pour la vie du process (les migrations ne font
 * qu'avancer, et l'image ne change pas) : le résultat se garde. Une base en
 * retard se relit à chaque appel, pour que `/health` repasse au vert dès la
 * migration appliquée.
 */
export class SchemaGuard {
  private upToDate = false;

  constructor(
    private readonly prisma: Pick<PrismaClient, "$queryRaw">,
    private readonly shipped: () => string[] = shippedMigrations,
  ) {}

  /** Les migrations qui manquent à la base ; vide quand le schéma suit le code. */
  async pending(): Promise<string[]> {
    if (this.upToDate) return [];

    const rows = await this.prisma.$queryRaw<{ migration_name: string }[]>`
      SELECT migration_name FROM _prisma_migrations
      WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL`;
    const missing = missingMigrations(
      this.shipped(),
      rows.map((row) => row.migration_name),
    );

    this.upToDate = missing.length === 0;
    return missing;
  }
}
