import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { hashSessionToken } from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";
import {
  serializeAccount,
  signInWithIdentity,
  signInWithPassword,
  signUpWithPassword,
  type IssuedSession,
} from "../services/accounts.js";
import { requestPasswordReset, resetPassword } from "../services/passwordReset.js";

/**
 * Entrée dans un compte. Ces routes ne sont pas authentifiées — ce sont elles
 * qui délivrent le token — sauf `/me` et `/signout`, qui exigent une session.
 */

/** Mêmes règles que l'app iOS (`PasswordRule`, dans `MemoBookCore`). */
const password = z
  .string()
  .min(8, "8 caractères minimum.")
  .refine((value) => /\p{L}/u.test(value), "Au moins une lettre.")
  .refine((value) => /\d/.test(value), "Au moins un chiffre.");

const signUpBody = z.object({
  email: z.string().email(),
  password,
  firstName: z.string().trim().min(1).max(100).optional(),
  lastName: z.string().trim().min(1).max(100).optional(),
});

const signInBody = z.object({
  email: z.string().email(),
  // Volontairement sans règle de complexité : les mots de passe déjà en base
  // n'ont pas à passer la validation d'aujourd'hui pour pouvoir se connecter.
  password: z.string().min(1),
});

const forgotPasswordBody = z.object({
  email: z.string().email(),
});

const resetPasswordBody = z.object({
  token: z.string().min(1),
  password,
});

const appleBody = z.object({
  identityToken: z.string().min(1),
  nonce: z.string().min(1),
  firstName: z.string().trim().max(100).optional(),
  lastName: z.string().trim().max(100).optional(),
});

const googleBody = z.object({
  identityToken: z.string().min(1),
});

export function registerAuthRoutes(app: FastifyInstance, context: AppContext): void {
  app.post("/v1/auth/signup", async (request, reply) => {
    const body = signUpBody.parse(request.body ?? {});
    const session = await signUpWithPassword(context.prisma, body);
    return reply.code(201).send(serialize(session));
  });

  app.post("/v1/auth/signin", async (request, reply) => {
    const body = signInBody.parse(request.body ?? {});
    const session = await signInWithPassword(context.prisma, body);
    return reply.send(serialize(session));
  });

  /**
   * « Mot de passe oublié ». 202 et non 204 : l'e-mail est accepté, pas
   * encore arrivé. Une adresse sans compte fait un 404 `unknown_account` —
   * voir `services/passwordReset.ts` pour pourquoi on le dit.
   */
  app.post("/v1/auth/password/forgot", async (request, reply) => {
    const body = forgotPasswordBody.parse(request.body ?? {});
    await requestPasswordReset(context.prisma, context.mailer, body.email);
    return reply.code(202).send();
  });

  /**
   * Le nouveau mot de passe, avec le secret reçu par e-mail. Répond comme
   * `/signin` : la session est ouverte, l'app entre directement.
   */
  app.post("/v1/auth/password/reset", async (request, reply) => {
    const body = resetPasswordBody.parse(request.body ?? {});
    const session = await resetPassword(context.prisma, body);
    return reply.send(serialize(session));
  });

  app.post("/v1/auth/apple", async (request, reply) => {
    const body = appleBody.parse(request.body ?? {});
    const identity = await context.socialVerifier.verifyApple(
      body.identityToken,
      body.nonce,
    );
    const session = await signInWithIdentity(context.prisma, identity, body);
    return reply.send(serialize(session));
  });

  app.post("/v1/auth/google", async (request, reply) => {
    const body = googleBody.parse(request.body ?? {});
    const identity = await context.socialVerifier.verifyGoogle(body.identityToken);
    const session = await signInWithIdentity(context.prisma, identity);
    return reply.send(serialize(session));
  });
}

/** Routes qui exigent déjà une session ouverte. */
export function registerSessionRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/auth/me", async (request, reply) => {
    // `requireAccount` l'a forcément renseigné ; le vérifier rend le type
    // honnête plutôt que de passer un `undefined` à Prisma.
    const accountId = request.accountId;
    if (!accountId) throw HttpError.unauthorized();

    const account = await context.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
    });
    return reply.send({ account: serializeAccount(account) });
  });

  app.post("/v1/auth/signout", async (request, reply) => {
    // On ne ferme que la session présentée : se déconnecter d'un téléphone ne
    // doit pas déconnecter les autres appareils.
    const token = request.headers.authorization?.replace(/^Bearer\s+/i, "").trim();
    if (token) {
      await context.prisma.session.deleteMany({
        where: { tokenHash: hashSessionToken(token) },
      });
    }
    return reply.code(204).send();
  });
}

function serialize(session: IssuedSession) {
  return {
    token: session.token,
    expiresAt: session.expiresAt.toISOString(),
    account: serializeAccount(session.account),
  };
}
