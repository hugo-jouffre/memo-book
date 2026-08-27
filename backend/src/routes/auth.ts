import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { generateToken, hashToken, normalizeEmail } from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";
import {
  checkPassword,
  hashPassword,
  passwordProblemMessage,
  verifyPassword,
} from "../lib/password.js";
import { deviceIdOf, userIdOf } from "../plugins/auth.js";
import {
  attachDevice,
  findUserByEmail,
  openSession,
  type AuthenticatedSession,
} from "../services/accounts.js";
import { SOCIAL_PROVIDERS } from "../services/socialLogin.js";

const email = z.string().trim().min(1, "l'email est requis").email("email invalide");
const name = z.string().trim().min(1).max(100);
const password = z.string().min(1, "le mot de passe est requis");

/**
 * Le jeton de l'appareil anonyme courant. Facultatif : sans lui la connexion
 * marche, mais les carnets déjà enregistrés sur cet appareil ne suivent pas.
 */
const deviceToken = z.string().min(1).optional();

/** Le flag local du Welcome Screen, poussé au serveur à la première occasion. */
const hasSeenOnboarding = z.boolean().optional();

const signupBody = z.object({
  firstName: name,
  lastName: name,
  email,
  password,
  deviceToken,
  hasSeenOnboarding,
});

const loginBody = z.object({ email, password, deviceToken, hasSeenOnboarding });

const forgotPasswordBody = z.object({ email });

const resetPasswordBody = z.object({
  token: z.string().min(1),
  newPassword: z.string().min(1),
});

const socialBody = z.object({
  /** Jeton d'identité renvoyé par le fournisseur (JWT Apple, `id_token`…). */
  credential: z.string().min(1),
  deviceToken,
  hasSeenOnboarding,
});

const socialCompleteBody = z.object({
  socialToken: z.string().min(1),
  firstName: name,
  lastName: name,
  email,
  deviceToken,
  hasSeenOnboarding,
});

const providerParams = z.object({ provider: z.enum(SOCIAL_PROVIDERS) });

/** Refuse un mot de passe qui ne tient pas la politique, avec le message exact. */
function assertPasswordPolicy(value: string): void {
  const problem = checkPassword(value);
  if (problem) throw HttpError.badRequest(passwordProblemMessage(problem), problem);
}

/**
 * Routes de compte : inscription, connexion, mot de passe oublié, connexion
 * tierce. Toutes non authentifiées sauf `GET /v1/auth/me` et `POST
 * /v1/auth/logout`, qui vivent derrière `requireCaller` (voir `app.ts`).
 *
 * Deux règles tenues partout :
 *
 *   - **aucune réponse ne révèle si un email existe**, sauf sur
 *     `forgot-password`, où le détail fonctionnel le demande explicitement
 *     (l'écran *Mdp oublié - compte inexistant*) ;
 *   - **aucun mot de passe ne sort d'ici**, ni en réponse, ni dans un log.
 */
export function registerAuthRoutes(app: FastifyInstance, context: AppContext): void {
  app.post("/v1/auth/signup", async (request, reply) => {
    const body = signupBody.parse(request.body ?? {});
    assertPasswordPolicy(body.password);

    const address = normalizeEmail(body.email);
    if (await findUserByEmail(context.prisma, address)) {
      throw HttpError.conflict("Un compte existe déjà avec cette adresse.");
    }

    const user = await context.prisma.user.create({
      data: {
        email: address,
        passwordHash: await hashPassword(body.password),
        firstName: body.firstName,
        lastName: body.lastName,
        hasSeenOnboarding: body.hasSeenOnboarding ?? false,
      },
      select: { id: true, hasSeenOnboarding: true },
    });

    return reply.code(201).send(await finishSignIn(context, user, body.deviceToken));
  });

  app.post("/v1/auth/login", async (request) => {
    const body = loginBody.parse(request.body ?? {});
    const user = await findUserByEmail(context.prisma, body.email);

    // Un compte sans mot de passe est un compte créé via un fournisseur tiers.
    // Le message reste le même : dire « ce compte passe par Apple » indiquerait
    // déjà que l'adresse existe.
    if (!user?.passwordHash || !(await verifyPassword(user.passwordHash, body.password))) {
      throw new HttpError(401, "Email ou mot de passe incorrect.", "invalid_credentials");
    }

    return finishSignIn(
      context,
      await markOnboardingSeen(context, user, body.hasSeenOnboarding),
      body.deviceToken,
    );
  });

  app.post("/v1/auth/forgot-password", async (request) => {
    const body = forgotPasswordBody.parse(request.body ?? {});
    const user = await findUserByEmail(context.prisma, body.email);

    // Ici, et seulement ici, l'existence du compte est révélée : c'est ce qui
    // fait exister l'écran *Mdp oublié - compte inexistant*, qui propose de
    // créer un compte plutôt que de laisser attendre un email qui ne vient pas.
    if (!user) {
      throw HttpError.notFound("Aucun compte n'est associé à cette adresse.");
    }

    const token = generateToken();
    const expiresAt = new Date(
      Date.now() + context.env.PASSWORD_RESET_TTL_MINUTES * 60 * 1000,
    );

    await context.prisma.passwordReset.create({
      data: { userId: user.id, tokenHash: hashToken(token), expiresAt },
    });

    const link = `${context.env.APP_DEEP_LINK_SCHEME}://reset-password?token=${token}`;

    // L'envoi n'est pas attendu par l'app : le détail fonctionnel demande une
    // redirection immédiate vers *Connection*. Un échec d'envoi est journalisé,
    // il ne transforme pas une demande valide en erreur à l'écran.
    void context.mailer
      .send({
        to: user.email,
        subject: "Reconfigure ton mot de passe MemoBook",
        text: [
          `Bonjour ${user.firstName},`,
          "",
          "Tu as demandé à reconfigurer ton mot de passe MemoBook.",
          `Ouvre ce lien depuis ton iPhone : ${link}`,
          "",
          `Le lien est valable ${context.env.PASSWORD_RESET_TTL_MINUTES} minutes et ne fonctionne qu'une fois.`,
          "Si tu n'es pas à l'origine de cette demande, ignore ce message.",
        ].join("\n"),
      })
      .catch((cause: unknown) => {
        context.logger.error({ cause }, "Envoi de l'email de réinitialisation échoué");
      });

    return { message: "email_sent" };
  });

  app.post("/v1/auth/reset-password", async (request) => {
    const body = resetPasswordBody.parse(request.body ?? {});
    assertPasswordPolicy(body.newPassword);

    const reset = await context.prisma.passwordReset.findUnique({
      where: { tokenHash: hashToken(body.token) },
      select: { id: true, userId: true, expiresAt: true, usedAt: true },
    });

    const expired = !reset || reset.usedAt !== null || reset.expiresAt.getTime() <= Date.now();
    if (expired) {
      throw HttpError.badRequest(
        "Ce lien n'est plus valable. Relance la procédure depuis l'écran de connexion.",
        "invalid_or_expired_token",
      );
    }

    await context.prisma.$transaction([
      context.prisma.user.update({
        where: { id: reset.userId },
        data: { passwordHash: await hashPassword(body.newPassword) },
      }),
      context.prisma.passwordReset.update({
        where: { id: reset.id },
        data: { usedAt: new Date() },
      }),
      // Changer de mot de passe ferme les sessions ouvertes : si quelqu'un
      // d'autre était connecté, il ne l'est plus.
      context.prisma.session.deleteMany({ where: { userId: reset.userId } }),
      // Les autres demandes en cours n'ont plus lieu d'être.
      context.prisma.passwordReset.deleteMany({
        where: { userId: reset.userId, usedAt: null },
      }),
    ]);

    return { message: "password_updated" };
  });

  app.post("/v1/auth/social/:provider", async (request) => {
    const { provider } = providerParams.parse(request.params);
    const body = socialBody.parse(request.body ?? {});

    const profile = await context.socialVerifier.verify(provider, body.credential);

    const identity = await context.prisma.socialIdentity.findUnique({
      where: { provider_subject: { provider, subject: profile.subject } },
      select: { user: { select: { id: true, hasSeenOnboarding: true } } },
    });

    // Compte connu : on ouvre la session, sans repasser par un formulaire.
    if (identity) {
      return {
        status: "signed_in" as const,
        ...(await finishSignIn(
          context,
          await markOnboardingSeen(context, identity.user, body.hasSeenOnboarding),
          body.deviceToken,
        )),
      };
    }

    // Compte inconnu : l'app affiche *Complète tes informations* plutôt que de
    // créer un compte en silence. Le `socialToken` renvoyé est ce qu'elle
    // repostera sur `/v1/auth/social/complete`.
    return {
      status: "profile_required" as const,
      socialToken: body.credential,
      provider,
      firstName: profile.firstName ?? null,
      lastName: profile.lastName ?? null,
      email: profile.email ?? null,
    };
  });

  app.post("/v1/auth/social/complete", async (request, reply) => {
    const body = socialCompleteBody.parse(request.body ?? {});

    const provider = SOCIAL_PROVIDERS.find((candidate) =>
      body.socialToken.startsWith(`${candidate}:`),
    );
    if (!provider) {
      throw HttpError.badRequest("Jeton de connexion invalide.", "invalid_social_token");
    }

    const profile = await context.socialVerifier.verify(provider, body.socialToken);
    const address = normalizeEmail(body.email);

    const existing = await context.prisma.socialIdentity.findUnique({
      where: { provider_subject: { provider, subject: profile.subject } },
      select: { user: { select: { id: true, hasSeenOnboarding: true } } },
    });

    // Deux envois du formulaire, ou un retour en arrière : on rouvre une
    // session sur le compte déjà créé au lieu de refuser.
    if (existing) {
      return finishSignIn(context, existing.user, body.deviceToken);
    }

    if (await findUserByEmail(context.prisma, address)) {
      throw HttpError.conflict("Un compte existe déjà avec cette adresse.");
    }

    const user = await context.prisma.user.create({
      data: {
        email: address,
        firstName: body.firstName,
        lastName: body.lastName,
        hasSeenOnboarding: body.hasSeenOnboarding ?? false,
        identities: {
          create: {
            provider,
            subject: profile.subject,
            ...(profile.email ? { email: profile.email } : {}),
          },
        },
      },
      select: { id: true, hasSeenOnboarding: true },
    });

    return reply.code(201).send(await finishSignIn(context, user, body.deviceToken));
  });
}

/**
 * Routes de compte qui exigent une session ouverte. Enregistrées avec le reste
 * de `/v1` protégé.
 */
export function registerAccountRoutes(app: FastifyInstance, context: AppContext): void {
  /** Ce que le Splash Screen interroge pour savoir si la session tient encore. */
  app.get("/v1/auth/me", async (request) => {
    const user = await context.prisma.user.findUnique({
      where: { id: userIdOf(request) },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        hasSeenOnboarding: true,
      },
    });
    if (!user) throw HttpError.notFound("Compte introuvable.");

    return { user, deviceId: deviceIdOf(request) };
  });

  app.post("/v1/auth/logout", async (request, reply) => {
    const token = request.headers.authorization?.replace(/^Bearer\s+/i, "").trim();
    if (token) {
      await context.prisma.session.deleteMany({ where: { tokenHash: hashToken(token) } });
    }
    return reply.code(204).send();
  });
}

/** Rattache l'appareil courant, puis ouvre la session. */
async function finishSignIn(
  context: AppContext,
  user: { id: string; hasSeenOnboarding: boolean },
  token: string | undefined,
): Promise<AuthenticatedSession> {
  const deviceId = await attachDevice(context.prisma, user.id, token);
  return openSession(context, user, deviceId);
}

/**
 * Le Welcome Screen a pu être vu avant que le compte existe : le flag local
 * remonte à la première connexion. Il ne redescend jamais à `false` — avoir vu
 * l'écran une fois ne s'annule pas.
 */
async function markOnboardingSeen<T extends { id: string; hasSeenOnboarding: boolean }>(
  context: AppContext,
  user: T,
  seenLocally: boolean | undefined,
): Promise<T> {
  if (!seenLocally || user.hasSeenOnboarding) return user;

  await context.prisma.user.update({
    where: { id: user.id },
    data: { hasSeenOnboarding: true },
  });

  return { ...user, hasSeenOnboarding: true };
}
