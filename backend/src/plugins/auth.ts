import type { FastifyInstance, FastifyRequest } from "fastify";
import type { AppContext } from "../context.js";
import {
  hashDeviceToken,
  hashSessionToken,
  parseBearerToken,
  sessionExpiry,
} from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";

declare module "fastify" {
  interface FastifyRequest {
    /** Renseigné par `requireDevice`. */
    deviceId?: string;

    /** Renseigné par `requireAccount`. */
    accountId?: string;
  }
}

/**
 * Le seul endroit du back-end qui sait comment un appelant est identifié.
 * Passer à de vrais comptes utilisateur se fera ici, sans toucher aux routes.
 */
export function createRequireDevice(context: AppContext) {
  return async function requireDevice(request: FastifyRequest): Promise<void> {
    const token = parseBearerToken(request.headers.authorization);
    if (!token) throw HttpError.unauthorized();

    const device = await context.prisma.device.findUnique({
      where: { tokenHash: hashDeviceToken(token) },
      select: { id: true },
    });

    if (!device) throw HttpError.unauthorized();

    request.deviceId = device.id;

    // `lastSeenAt` sert au ménage des appareils inactifs ; son échec ne doit
    // pas faire échouer la requête de l'utilisateur.
    void context.prisma.device
      .update({ where: { id: device.id }, data: { lastSeenAt: new Date() } })
      .catch((cause: unknown) => {
        context.logger.debug({ cause }, "Mise à jour de lastSeenAt ignorée");
      });
  };
}

/** Récupère le device d'une requête déjà passée par `requireDevice`. */
export function deviceIdOf(request: FastifyRequest): string {
  if (!request.deviceId) throw HttpError.unauthorized();
  return request.deviceId;
}

export function registerAuthDecorator(app: FastifyInstance): void {
  app.decorateRequest("deviceId", undefined);
}

/**
 * Exige une session de compte ouverte. C'est la version « vrais comptes » de
 * `requireDevice`, appelée à la remplacer quand la propriété des carnets sera
 * passée de l'appareil au compte.
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
