import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { photosDiagnostic, pipelineDiagnostic } from "../services/renderDiagnostics.js";

/**
 * Readiness réelle : on interroge la base et la file, on ne se contente pas de
 * répondre 200 parce que le process est vivant.
 *
 * Et on vérifie que la base **a le schéma de ce code** : c'est ce contrôle que
 * Railway attend avant de basculer le trafic sur un déploiement. Un code parti
 * sans sa migration échoue donc ici, au lieu de rendre 500 à l'app — voir
 * `lib/schemaGuard.ts`.
 */
export function registerHealthRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/health", async (request, reply) => {
    const [database, queue, pendingMigrations] = await Promise.all([
      context.prisma
        .$queryRaw`SELECT 1`.then(() => true)
        .catch(() => false),
      context.queue.healthy().catch(() => false),
      // `null` : la base ne répond pas, et `database` le dit déjà.
      context.schema.pending().catch(() => null),
    ]);

    const schema = pendingMigrations === null ? null : pendingMigrations.length === 0;
    const healthy = database && queue && schema === true;

    if (pendingMigrations?.length) {
      request.log.error(
        { pendingMigrations },
        "Schéma en retard sur le code : `prisma migrate deploy` n'a pas tourné avant ce déploiement.",
      );
    }

    return reply.code(healthy ? 200 : 503).send({
      status: healthy ? "ok" : "degraded",
      checks: {
        database: database ? "ok" : "down",
        queue: queue ? "ok" : "down",
        schema: schema === null ? "unknown" : schema ? "ok" : "behind",
      },
      ...(pendingMigrations?.length ? { pendingMigrations } : {}),
      // Indique si le pipeline appelle vraiment OpenAI/APITemplate ou tourne
      // sur les implémentations simulées — première question qu'on se pose en
      // débuggant un carnet vide.
      pipelineMode: context.env.live ? "live" : "fake",
      // Pourquoi un carnet sortirait sans photos, lisible d'un `curl` : moteur
      // retenu et adresse à laquelle il ira les chercher. Voir
      // `services/renderDiagnostics.ts`. Attention, c'est le diagnostic de
      // **ce service** : le worker, qui compose vraiment, annonce le sien au
      // démarrage dans ses logs — ses variables peuvent différer.
      photos: photosDiagnostic(context.env),
      // **Ce qui casse en silence** (T274) : les carnets sortent-ils encore ?
      // Deux fois en un mois, la composition s'est arrêtée faute de crédit
      // chez un fournisseur, et `/health` répondait `ok` — il ne regardait que
      // ce qui tient le service debout, rien de ce qu'il produit. Ces chiffres
      // ne font **pas** tomber la sonde : un rendu raté ne doit bloquer ni un
      // déploiement ni le trafic.
      pipeline: database ? await pipelineDiagnostic(context.prisma) : null,
    });
  });
}
