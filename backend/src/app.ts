import multipart from "@fastify/multipart";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { ZodError } from "zod";
import type { AppContext } from "./context.js";
import { registerJobs } from "./jobs/index.js";
import { isDatabaseUnavailable } from "./lib/databasePool.js";
import { HttpError } from "./lib/httpError.js";
import { createRequireAccount, registerAuthDecorator } from "./plugins/auth.js";
import { registerAccountRoutes } from "./routes/accounts.js";
import { registerDataExportPageRoutes } from "./routes/dataExportPage.js";
import { registerAppStoreRoutes, registerAppStoreWebhookRoutes } from "./routes/appStore.js";
import { registerAuthRoutes, registerSessionRoutes } from "./routes/auth.js";
import { registerDeviceRoutes } from "./routes/devices.js";
import { registerEntryRoutes } from "./routes/entries.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerHomeRoutes, registerWelcomeRoutes } from "./routes/home.js";
import { registerLocalRenderRoutes } from "./routes/localRenders.js";
import { registerMemoRoutes } from "./routes/memos.js";
import { registerNotificationRoutes } from "./routes/notifications.js";
import { registerOrderRoutes } from "./routes/orders.js";
import { registerPaymentMethodRoutes } from "./routes/paymentMethods.js";
import { registerPasswordResetPageRoutes } from "./routes/passwordResetPage.js";
import { registerAvatarRoutes, registerProfileRoutes } from "./routes/profile.js";
import { registerStepRoutes } from "./routes/steps.js";
import { configureAvatarUrls } from "./services/avatars.js";
import { isValidTimeZone } from "./services/localCalendar.js";
import { registerRenderRoutes } from "./routes/renders.js";
import { registerStripeWebhookRoutes } from "./routes/stripeWebhook.js";
import { registerBookPreviewRoutes } from "./routes/bookPreview.js";
import { registerChatRoutes } from "./routes/chat.js";
import { registerTripSettingsRoutes } from "./routes/tripSettings.js";
import { registerCoverPhotoRoutes, registerCoverRoutes } from "./routes/covers.js";

/** Combien de temps un fuseau confirmé dispense de le réécrire. */
const TIME_ZONE_MEMO_MS = 10 * 60 * 1000;

/**
 * **L'en-tête `X-Time-Zone`** (Hugo, 03/10/2026) : l'app envoie le fuseau du
 * téléphone (`Europe/Paris`) sur chaque appel, et le compte le retient.
 *
 * Il ne venait jusqu'ici qu'avec le jeton APNs : un voyageur qui refusait les
 * notifications n'avait jamais de fuseau, et vivait à l'heure de Paris. Or le
 * crédit du jour se recharge **à minuit chez celui qui raconte**
 * (`services/dailyCredit.ts`) — à Tokyo comme à Montréal.
 *
 * Une écriture **seulement quand il change** : l'`UPDATE` est conditionnel, et
 * un fuseau déjà confirmé par ce process n'est pas réécrit avant dix minutes
 * (la mémoire est par process ; au pire, un autre serveur réécrit une fois).
 * Un en-tête absent, ou un fuseau qu'`Intl` ne connaît pas, ne change rien. Un
 * échec d'écriture ne fait jamais échouer la requête.
 */
function createTimeZoneSync(context: AppContext) {
  const confirmed = new Map<string, { timeZone: string; at: number }>();

  return async function syncTimeZone(request: FastifyRequest): Promise<void> {
    const accountId = request.accountId;
    const header = request.headers["x-time-zone"];
    const raw = typeof header === "string" ? header.trim() : "";
    if (!accountId || raw.length === 0 || raw.length > 64 || !isValidTimeZone(raw)) return;

    // La forme canonique : « europe/paris » est le même fuseau, et ne doit pas
    // réécrire la colonne à chaque appel.
    const timeZone = new Intl.DateTimeFormat("en-US", { timeZone: raw }).resolvedOptions().timeZone;
    const known = confirmed.get(accountId);
    if (known && known.timeZone === timeZone && Date.now() - known.at < TIME_ZONE_MEMO_MS) return;

    try {
      await context.prisma.account.updateMany({
        where: { id: accountId, OR: [{ timeZone: null }, { timeZone: { not: timeZone } }] },
        data: { timeZone },
      });
      if (confirmed.size > 10_000) confirmed.clear();
      confirmed.set(accountId, { timeZone, at: Date.now() });
    } catch (cause) {
      request.log.warn({ err: cause }, "Fuseau du compte non enregistré");
    }
  };
}

export async function buildApp(context: AppContext): Promise<FastifyInstance> {
  // Fastify construit son propre logger de requêtes ; `context.logger` reste le
  // logger applicatif utilisé par les jobs, hors cycle de vie HTTP.
  const app = Fastify({ logger: { level: context.env.LOG_LEVEL } });

  await app.register(multipart, {
    limits: { fileSize: 25 * 1024 * 1024, files: 1 },
  });

  registerAuthDecorator(app);
  registerJobs(context);
  configureAvatarUrls(context.env);

  app.setErrorHandler((error: Error & { statusCode?: number; code?: string }, request, reply) => {
    if (error instanceof HttpError) {
      return reply
        .code(error.statusCode)
        .send({ ...error.details, error: error.code ?? "error", message: error.message });
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

    // La base n'est pas joignable — pool saturé, serveur absent. Ce n'est pas
    // un bug : un 503 le dit à l'app, qui sait qu'un nouvel essai a du sens,
    // et le message ne parle pas d'« erreur interne » pour une panne passagère.
    if (isDatabaseUnavailable(error)) {
      request.log.error({ err: error }, "Base de données indisponible");
      return reply.code(503).send({
        error: "database_unavailable",
        message: "Le serveur est momentanément saturé, réessaie dans un instant.",
      });
    }

    request.log.error({ err: error }, "Erreur non gérée");
    // Une phrase qui dit **à qui** est la panne et **quoi faire**, pas un code.
    // « Erreur interne du serveur » laissait le voyageur devant un mur : il
    // cherchait ce qu'il avait mal fait, alors que c'est nous (Hugo, 15/09/2026).
    return reply.code(500).send({
      error: "internal_error",
      message:
        "Notre serveur a rencontré un problème inattendu. Ce n’est pas de ton fait : réessaie dans un instant, et si ça continue, écris-nous depuis « Besoin d’aide ? ».",
    });
  });

  registerHealthRoutes(app, context);

  // Stripe n'a pas de compte MemoBook : son webhook ne peut pas passer par
  // l'identification. C'est la signature de l'en-tête `stripe-signature` qui
  // l'authentifie, et elle vaut mieux qu'un jeton — elle porte sur le corps.
  await registerStripeWebhookRoutes(app, context);
  registerDeviceRoutes(app, context);

  // Apple non plus : ses notifications d'abonnement sont des JWS, et c'est leur
  // chaîne de certificats qui les authentifie.
  registerAppStoreWebhookRoutes(app, context);

  // L'écran de bienvenue s'affiche avant toute connexion : sa route ne peut pas
  // en exiger une.
  registerWelcomeRoutes(app, context);

  // Entrée dans un compte : ce sont ces routes qui délivrent le token, elles ne
  // peuvent donc pas en exiger un.
  registerAuthRoutes(app, context);

  // La page que le bouton de l'e-mail « mot de passe oublié » ouvre dans un
  // navigateur, et qui relaie vers l'app. Publique par nature : on y arrive
  // sans session, c'est pour en ouvrir une.
  registerPasswordResetPageRoutes(app);

  // La page du lien « Télécharger mes données », et l'archive derrière son
  // bouton. Publiques aussi : on y arrive depuis une boîte mail, et c'est le
  // secret du lien qui ouvre — pas une session.
  registerDataExportPageRoutes(app, context);

  // Tout ce qui appartient à quelqu'un, sous **une seule** identification : la
  // session de compte. Le token d'appareil n'ouvre plus rien — un carnet a
  // toujours un propriétaire, et c'est un compte.
  await app.register(async (accountRoutes) => {
    accountRoutes.addHook("preHandler", createRequireAccount(context));
    // Après l'identification : il faut savoir à quel compte parle le fuseau.
    accountRoutes.addHook("preHandler", createTimeZoneSync(context));
    registerSessionRoutes(accountRoutes, context);
    registerAccountRoutes(accountRoutes, context);
    registerHomeRoutes(accountRoutes, context);
    registerProfileRoutes(accountRoutes, context);
    registerMemoRoutes(accountRoutes, context);
    registerEntryRoutes(accountRoutes, context);
    registerRenderRoutes(accountRoutes, context);
    registerStepRoutes(accountRoutes, context);
    registerOrderRoutes(accountRoutes, context);
    registerTripSettingsRoutes(accountRoutes, context);
    registerCoverRoutes(accountRoutes, context);
    registerChatRoutes(accountRoutes, context);
    registerBookPreviewRoutes(accountRoutes, context);
    registerAppStoreRoutes(accountRoutes, context);
    registerPaymentMethodRoutes(accountRoutes, context);
    registerNotificationRoutes(accountRoutes, context);
  });

  // Uniquement en mode de rendu local : sert les PDF produits sur le disque.
  registerLocalRenderRoutes(app, context);

  // Les photos de profil, en HTTP simple : `AsyncImage` n'envoie pas de
  // session, et un avatar se montre à ceux qui partagent le voyage.
  registerAvatarRoutes(app, context);
  registerCoverPhotoRoutes(app, context);

  return app;
}
