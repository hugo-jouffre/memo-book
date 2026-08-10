import type { FastifyInstance, FastifyRequest } from "fastify";
import type { AppContext } from "../context.js";
import { hashDeviceToken, parseBearerToken } from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";

declare module "fastify" {
  interface FastifyRequest {
    /** Renseigné par `requireDevice`. */
    deviceId?: string;
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
