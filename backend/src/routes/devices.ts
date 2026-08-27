import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { generateToken, hashToken } from "../lib/auth.js";

const registerBody = z.object({
  platform: z.enum(["ios", "android", "web"]).default("ios"),
});

/**
 * Crée l'identité anonyme de l'appareil, au tout premier lancement et avant
 * qu'un compte existe. Le token n'est renvoyé qu'ici, en clair, une seule fois.
 */
export function registerDeviceRoutes(app: FastifyInstance, context: AppContext): void {
  app.post("/v1/devices", async (request, reply) => {
    const body = registerBody.parse(request.body ?? {});
    const token = generateToken();

    const device = await context.prisma.device.create({
      data: { tokenHash: hashToken(token), platform: body.platform },
      select: { id: true, platform: true, createdAt: true },
    });

    return reply.code(201).send({
      deviceId: device.id,
      token,
      platform: device.platform,
      createdAt: device.createdAt.toISOString(),
    });
  });
}
