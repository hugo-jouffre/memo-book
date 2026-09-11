import multipart from "@fastify/multipart";
import Fastify, { type FastifyInstance } from "fastify";
import { ZodError } from "zod";
import type { AppContext } from "./context.js";
import { registerJobs } from "./jobs/index.js";
import { HttpError } from "./lib/httpError.js";
import { createRequireAccount, registerAuthDecorator } from "./plugins/auth.js";
import { registerAccountRoutes } from "./routes/accounts.js";
import { registerAuthRoutes, registerSessionRoutes } from "./routes/auth.js";
import { registerDeviceRoutes } from "./routes/devices.js";
import { registerEntryRoutes } from "./routes/entries.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerHomeRoutes, registerWelcomeRoutes } from "./routes/home.js";
import { registerLocalRenderRoutes } from "./routes/localRenders.js";
import { registerMemoRoutes } from "./routes/memos.js";
import { registerOrderRoutes } from "./routes/orders.js";
import { registerProfileRoutes } from "./routes/profile.js";
import { registerRenderRoutes } from "./routes/renders.js";
import { registerBookPreviewRoutes } from "./routes/bookPreview.js";
import { registerTripSettingsRoutes } from "./routes/tripSettings.js";
import { registerWalletRoutes } from "./routes/wallet.js";

export async function buildApp(context: AppContext): Promise<FastifyInstance> {
  // Fastify construit son propre logger de requêtes ; `context.logger` reste le
  // logger applicatif utilisé par les jobs, hors cycle de vie HTTP.
  const app = Fastify({ logger: { level: context.env.LOG_LEVEL } });

  await app.register(multipart, {
    limits: { fileSize: 25 * 1024 * 1024, files: 1 },
  });

  registerAuthDecorator(app);
  registerJobs(context);

  app.setErrorHandler((error: Error & { statusCode?: number; code?: string }, request, reply) => {
    if (error instanceof HttpError) {
      return reply
        .code(error.statusCode)
        .send({ error: error.code ?? "error", message: error.message });
    }

    if (error instanceof ZodError) {
      return reply.code(400).send({
        error: "validation_error",
        message: "Requête invalide.",
        details: error.issues.map((issue) => ({
          path: issue.path.join("."),
          message: issue.message,
        })),
      });
    }

    // Erreurs de parsing/limites levées par @fastify/multipart et Fastify.
    if (typeof error.statusCode === "number" && error.statusCode < 500) {
      return reply
        .code(error.statusCode)
        .send({ error: error.code ?? "bad_request", message: error.message });
    }

    request.log.error({ err: error }, "Erreur non gérée");
    return reply
      .code(500)
      .send({ error: "internal_error", message: "Erreur interne du serveur." });
  });

  registerHealthRoutes(app, context);
  registerDeviceRoutes(app, context);

  // L'écran de bienvenue s'affiche avant toute connexion : sa route ne peut pas
  // en exiger une.
  registerWelcomeRoutes(app, context);

  // Entrée dans un compte : ce sont ces routes qui délivrent le token, elles ne
  // peuvent donc pas en exiger un.
  registerAuthRoutes(app, context);

  // Tout ce qui appartient à quelqu'un, sous **une seule** identification : la
  // session de compte. Le token d'appareil n'ouvre plus rien — un carnet a
  // toujours un propriétaire, et c'est un compte.
  await app.register(async (accountRoutes) => {
    accountRoutes.addHook("preHandler", createRequireAccount(context));
    registerSessionRoutes(accountRoutes, context);
    registerAccountRoutes(accountRoutes, context);
    registerHomeRoutes(accountRoutes, context);
    registerProfileRoutes(accountRoutes, context);
    registerMemoRoutes(accountRoutes, context);
    registerEntryRoutes(accountRoutes, context);
    registerRenderRoutes(accountRoutes, context);
    registerOrderRoutes(accountRoutes, context);
    registerTripSettingsRoutes(accountRoutes, context);
    registerBookPreviewRoutes(accountRoutes, context);
    registerWalletRoutes(accountRoutes, context);
  });

  // Uniquement en mode de rendu local : sert les PDF produits sur le disque.
  registerLocalRenderRoutes(app, context);

  return app;
}
