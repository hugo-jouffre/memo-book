import type { FastifyInstance, FastifyRequest } from "fastify";
import type { AppContext } from "../context.js";
import { hashToken, parseBearerToken } from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";

declare module "fastify" {
  interface FastifyRequest {
    /** Renseigné par `requireCaller`. Les carnets s'y rattachent. */
    deviceId?: string;
    /** Renseigné seulement quand l'appelant est connecté à un compte. */
    userId?: string;
  }
}

/**
 * Le seul endroit du back-end qui sait comment un appelant est identifié.
 *
 * Deux jetons y entrent, un seul concept en sort. Un **jeton de session** dit
 * quel compte parle, et l'appareil retenu est le `primaryDevice` du compte —
 * celui qui porte les carnets, quel que soit le téléphone utilisé. Un **jeton
 * d'appareil** dit qu'un appareil encore anonyme parle, comme avant l'arrivée
 * des comptes. Les routes et les jobs, eux, ne connaissent que
 * `request.deviceId` : rien n'a bougé de leur côté.
 */
export function createRequireCaller(context: AppContext) {
  return async function requireCaller(request: FastifyRequest): Promise<void> {
    const token = parseBearerToken(request.headers.authorization);
    if (!token) throw HttpError.unauthorized();

    const tokenHash = hashToken(token);

    const session = await context.prisma.session.findUnique({
      where: { tokenHash },
      select: {
        id: true,
        expiresAt: true,
        user: { select: { id: true, primaryDeviceId: true } },
      },
    });

    if (session) {
      if (session.expiresAt.getTime() <= Date.now()) {
        throw HttpError.unauthorized("Ta session a expiré. Reconnecte-toi.");
      }

      // Un compte sans appareil principal ne devrait pas exister : l'inscription
      // et la connexion en rattachent toujours un. Si le cas se présente, mieux
      // vaut un 401 lisible qu'une requête qui liste les carnets de personne.
      const deviceId = session.user.primaryDeviceId;
      if (!deviceId) {
        throw HttpError.unauthorized("Aucun appareil n'est rattaché à ce compte.");
      }

      request.userId = session.user.id;
      request.deviceId = deviceId;
      touch(context, { session: session.id, device: deviceId });
      return;
    }

    const device = await context.prisma.device.findUnique({
      where: { tokenHash },
      select: { id: true, userId: true },
    });

    if (!device) throw HttpError.unauthorized();

    request.deviceId = device.id;
    if (device.userId) request.userId = device.userId;
    touch(context, { device: device.id });
  };
}

/**
 * `lastSeenAt` sert au ménage des identités inactives ; son échec ne doit pas
 * faire échouer la requête de l'utilisateur.
 */
function touch(context: AppContext, ids: { device: string; session?: string }): void {
  const now = new Date();

  void context.prisma.device
    .update({ where: { id: ids.device }, data: { lastSeenAt: now } })
    .catch((cause: unknown) => {
      context.logger.debug({ cause }, "Mise à jour de lastSeenAt ignorée");
    });

  if (ids.session) {
    void context.prisma.session
      .update({ where: { id: ids.session }, data: { lastSeenAt: now } })
      .catch((cause: unknown) => {
        context.logger.debug({ cause }, "Mise à jour de lastSeenAt (session) ignorée");
      });
  }
}

/** Récupère l'appareil d'une requête déjà passée par `requireCaller`. */
export function deviceIdOf(request: FastifyRequest): string {
  if (!request.deviceId) throw HttpError.unauthorized();
  return request.deviceId;
}

/** Récupère le compte d'une requête, quand la route en exige un. */
export function userIdOf(request: FastifyRequest): string {
  if (!request.userId) throw HttpError.unauthorized();
  return request.userId;
}

export function registerAuthDecorator(app: FastifyInstance): void {
  app.decorateRequest("deviceId", undefined);
  app.decorateRequest("userId", undefined);
}
