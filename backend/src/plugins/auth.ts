import type { FastifyInstance, FastifyRequest } from "fastify";
import type { AppContext } from "../context.js";
import { hashSessionToken, parseBearerToken, sessionExpiry } from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";

declare module "fastify" {
  interface FastifyRequest {
    /** Renseigné par `requireAccount`. */
    accountId?: string;
  }
}

export function registerAuthDecorator(app: FastifyInstance): void {
  app.decorateRequest("accountId", undefined);
}

/**
 * Le seul endroit du back-end qui sait comment un appelant est identifié.
 *
 * Une **session de compte**, et rien d'autre : le token d'appareil ne donne
 * plus accès à quoi que ce soit d'appartenant à quelqu'un, depuis qu'un carnet
 * a toujours un propriétaire. Il ne sert plus qu'à s'enregistrer et à se
 * rattacher à un compte.
 */
export function createRequireAccount(context: AppContext) {
  return async function requireAccount(request: FastifyRequest): Promise<void> {
    const token = parseBearerToken(request.headers.authorization);
    if (!token) throw HttpError.unauthorized();

    const session = await context.prisma.session.findUnique({
      where: { tokenHash: hashSessionToken(token) },
      select: { id: true, accountId: true, expiresAt: true },
    });

    if (!session) throw HttpError.unauthorized();

    if (session.expiresAt <= new Date()) {
      // Une session périmée est supprimée à la première tentative : sans ça la
      // table ne fait que grossir, et une ligne morte reste une ligne qu'on
      // pourrait un jour ressusciter par erreur.
      await context.prisma.session.delete({ where: { id: session.id } }).catch(() => {});
      throw HttpError.unauthorized("Session expirée.");
    }

    request.accountId = session.accountId;

    // Session glissante : chaque usage repousse l'échéance. Quelqu'un qui
    // ouvre l'app toutes les semaines ne se fait jamais déconnecter ; celui qui
    // l'oublie trois mois, si. L'échec ne doit pas faire échouer la requête.
    void context.prisma.session
      .update({
        where: { id: session.id },
        data: { lastSeenAt: new Date(), expiresAt: sessionExpiry() },
      })
      .catch((cause: unknown) => {
        context.logger.debug({ cause }, "Prolongation de session ignorée");
      });
  };
}

/** Récupère le compte d'une requête déjà passée par `requireAccount`. */
export function accountIdOf(request: FastifyRequest): string {
  if (!request.accountId) throw HttpError.unauthorized();
  return request.accountId;
}
