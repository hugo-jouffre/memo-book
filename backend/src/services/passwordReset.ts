import type { PrismaClient } from "@prisma/client";
import { randomBytes } from "node:crypto";
import { hashSessionToken } from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";
import { hashPassword } from "../lib/password.js";
import { normalizeEmail, openSession, type IssuedSession } from "./accounts.js";
import type { Mailer } from "./mailer.js";

/**
 * « Mot de passe oublié », côté serveur.
 *
 * Une adresse sans compte est **refusée, et dite** : la feuille affiche « Il
 * n'existe aucun compte associé à cette adresse » et propose d'en créer un
 * (Hugo, 15/09/2026). C'est un choix assumé : la réponse permet de vérifier qui
 * a un compte, adresse par adresse — mais l'inscription le disait déjà (« Un
 * compte existe déjà avec cette adresse »), et masquer l'information ici
 * n'empêcherait pas de la déduire là.
 */

/** Le code que l'app reconnaît pour dessiner ce cas, et lui seul. */
export const UNKNOWN_ACCOUNT_CODE = "unknown_account";

/** Une demande vaut une demi-heure : le temps d'ouvrir sa boîte, pas plus. */
export const PASSWORD_RESET_TTL_MINUTES = 30;

export function passwordResetExpiry(from: Date = new Date()): Date {
  return new Date(from.getTime() + PASSWORD_RESET_TTL_MINUTES * 60 * 1000);
}

/** Même forme qu'un token de session : opaque, tiré au hasard, stocké haché. */
function generateResetToken(): string {
  return randomBytes(32).toString("base64url");
}

/**
 * Envoie l'e-mail de réinitialisation à `email`. Lève un 404
 * `unknown_account` si aucun compte n'y répond.
 *
 * Les demandes précédentes du compte sont retirées : un seul secret est
 * valable à la fois, et c'est le dernier envoyé — celui que la personne a
 * sous les yeux.
 *
 * Un compte entré uniquement par Apple ou Google (sans `passwordHash`) reçoit
 * l'e-mail quand même : choisir un mot de passe est précisément ce qui lui
 * ouvrira l'entrée par adresse.
 */
export async function requestPasswordReset(
  prisma: PrismaClient,
  mailer: Mailer,
  rawEmail: string,
): Promise<void> {
  const email = normalizeEmail(rawEmail);
  const account = await prisma.account.findUnique({ where: { email } });
  if (!account) {
    throw new HttpError(
      404,
      `Il n’existe aucun compte associé à l’adresse ${email}`,
      UNKNOWN_ACCOUNT_CODE,
    );
  }

  const token = generateResetToken();
  const expiresAt = passwordResetExpiry();

  await prisma.$transaction([
    prisma.passwordReset.deleteMany({ where: { accountId: account.id, usedAt: null } }),
    prisma.passwordReset.create({
      data: { accountId: account.id, tokenHash: hashSessionToken(token), expiresAt },
    }),
  ]);

  await mailer.sendPasswordReset({
    to: email,
    firstName: account.firstName,
    token,
    expiresAt,
  });
}

/** Le code que l'app reconnaît pour un lien périmé, consommé ou inventé. */
export const INVALID_RESET_TOKEN_CODE = "invalid_reset_token";

/**
 * Le lien de l'e-mail a été ouvert, et un nouveau mot de passe choisi.
 *
 * Trois choses dans la même transaction : le mot de passe change, la demande
 * est **consommée** (elle ne resservira pas), et **toutes les sessions du
 * compte sont fermées** — celui qui change son mot de passe parce qu'il craint
 * qu'on le lui ait pris doit savoir que l'autre téléphone est dehors. Puis une
 * session neuve s'ouvre pour l'appareil qui vient de le faire : on entre dans
 * l'app sans avoir à retaper ce qu'on vient d'écrire.
 *
 * Ouvrir le lien prouve qu'on lit la boîte : l'adresse en devient vérifiée,
 * ce qui compte pour le rattachement entre fournisseurs (`emailVerifiedAt`).
 */
export async function resetPassword(
  prisma: PrismaClient,
  input: { token: string; password: string },
): Promise<IssuedSession> {
  const reset = await prisma.passwordReset.findUnique({
    where: { tokenHash: hashSessionToken(input.token) },
    include: { account: true },
  });

  // Un seul message pour les trois cas — inexistant, consommé, expiré : la
  // personne ne peut rien en faire de différent, et détailler ne servirait
  // qu'à qui essaie des liens.
  if (!reset || reset.usedAt || reset.expiresAt.getTime() <= Date.now()) {
    throw new HttpError(
      400,
      "Ce lien n’est plus valable. Redemande un e-mail depuis « Mot de passe oublié ».",
      INVALID_RESET_TOKEN_CODE,
    );
  }

  const now = new Date();
  const [account] = await prisma.$transaction([
    prisma.account.update({
      where: { id: reset.accountId },
      data: {
        passwordHash: await hashPassword(input.password),
        emailVerifiedAt: reset.account.emailVerifiedAt ?? now,
      },
    }),
    prisma.passwordReset.update({ where: { id: reset.id }, data: { usedAt: now } }),
    prisma.session.deleteMany({ where: { accountId: reset.accountId } }),
  ]);

  return openSession(prisma, account);
}
