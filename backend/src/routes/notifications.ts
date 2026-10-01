import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { accountIdOf, sessionIdOf } from "../plugins/auth.js";
import { isValidTimeZone } from "../services/localCalendar.js";

/**
 * Les deux routes des notifications, côté app — `docs/notifications.md`.
 *
 * - `POST /v1/push-tokens` : le téléphone dit où le joindre. Appelée à chaque
 *   entrée dans l'app une fois l'autorisation donnée : Apple peut changer le
 *   jeton (restauration, réinstallation), et c'est aussi ce qui garde le
 *   fuseau à jour quand on change de pays.
 * - `POST /v1/notifications/:id/opened` : on a touché une notification. C'est
 *   le « comportement réel » qui ajuste le rythme du voyageur.
 */

const pushTokenBody = z.object({
  /** Le jeton APNs, en hexadécimal — 64 caractères aujourd'hui, plus demain. */
  token: z
    .string()
    .trim()
    .regex(/^[0-9a-fA-F]{32,200}$/, "Jeton APNs invalide.")
    .transform((value) => value.toLowerCase()),
  /** `sandbox` pour un build Xcode, `production` pour TestFlight et l'App Store. */
  environment: z.enum(["sandbox", "production"]),
  /** Le fuseau du téléphone, `Europe/Paris`. */
  timeZone: z.string().trim().max(64).optional(),
  appVersion: z.string().trim().max(40).optional(),
});

const deliveryParams = z.object({ id: z.string().uuid() });

export function registerNotificationRoutes(app: FastifyInstance, context: AppContext): void {
  app.post("/v1/push-tokens", async (request, reply) => {
    const accountId = accountIdOf(request);
    const sessionId = sessionIdOf(request);
    const body = pushTokenBody.parse(request.body ?? {});

    // Le même téléphone peut changer de main : le jeton est unique, la ligne
    // passe au compte et à la session qui l'envoient maintenant.
    await context.prisma.pushToken.upsert({
      where: { token: body.token },
      create: {
        token: body.token,
        environment: body.environment,
        appVersion: body.appVersion ?? null,
        accountId,
        sessionId,
      },
      update: {
        environment: body.environment,
        appVersion: body.appVersion ?? null,
        accountId,
        sessionId,
        lastSeenAt: new Date(),
      },
    });

    // Un fuseau qu'`Intl` ne connaît pas est ignoré, pas refusé : le jeton
    // compte plus que lui, et Paris reste le repli.
    if (body.timeZone && isValidTimeZone(body.timeZone)) {
      await context.prisma.account.update({
        where: { id: accountId },
        data: { timeZone: body.timeZone },
      });
    }

    return reply.code(204).send();
  });

  app.post("/v1/notifications/:id/opened", async (request, reply) => {
    const accountId = accountIdOf(request);
    const { id } = deliveryParams.parse(request.params);

    // Idempotent, et muet sur ce qui n'est pas à soi : la première ouverture
    // compte, les suivantes ne changent rien, et l'identifiant d'un autre
    // compte ne touche à rien.
    await context.prisma.notificationDelivery.updateMany({
      where: { id, accountId, openedAt: null },
      data: { openedAt: new Date() },
    });

    return reply.code(204).send();
  });
}
