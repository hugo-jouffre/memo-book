import type { Account, PrismaClient } from "@prisma/client";
import {
  generateSessionToken,
  hashSessionToken,
  sessionExpiry,
} from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";
import { hashPassword, verifyPassword } from "../lib/password.js";
import type { VerifiedIdentity } from "./socialIdentity.js";

export interface IssuedSession {
  /** En clair, et une seule fois : la base n'en garde que l'empreinte. */
  token: string;
  expiresAt: Date;
  account: Account;
}

/** Normalise une adresse pour la comparaison et le stockage. */
export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export async function openSession(
  prisma: PrismaClient,
  account: Account,
): Promise<IssuedSession> {
  const token = generateSessionToken();
  const expiresAt = sessionExpiry();

  await prisma.session.create({
    data: { accountId: account.id, tokenHash: hashSessionToken(token), expiresAt },
  });

  return { token, expiresAt, account };
}

export async function signUpWithPassword(
  prisma: PrismaClient,
  input: { email: string; password: string; firstName?: string; lastName?: string },
): Promise<IssuedSession> {
  const email = normalizeEmail(input.email);

  const existing = await prisma.account.findUnique({ where: { email } });
  if (existing) {
    // Message volontairement identique à celui d'une inscription réussie côté
    // produit ? Non : ici on assume de le dire. L'app propose « Connexion »
    // juste à côté, et masquer l'information n'empêcherait pas de la déduire
    // en tentant une connexion.
    throw HttpError.conflict("Un compte existe déjà avec cette adresse.");
  }

  const account = await prisma.account.create({
    data: {
      email,
      firstName: input.firstName?.trim() || null,
      lastName: input.lastName?.trim() || null,
      passwordHash: await hashPassword(input.password),
    },
  });

  return openSession(prisma, account);
}

export async function signInWithPassword(
  prisma: PrismaClient,
  input: { email: string; password: string },
): Promise<IssuedSession> {
  const account = await prisma.account.findUnique({
    where: { email: normalizeEmail(input.email) },
  });

  // Un seul message pour « adresse inconnue » et « mot de passe faux » : dire
  // laquelle des deux a échoué revient à publier la liste des comptes.
  const invalid = HttpError.unauthorized("Adresse ou mot de passe incorrect.");

  if (!account?.passwordHash) {
    // Compte inexistant, ou entré uniquement par Apple/Google. On hache quand
    // même une valeur bidon : sans ça, le temps de réponse dirait si l'adresse
    // existe.
    await verifyPassword(input.password, "scrypt$32768$8$1$AA$AA");
    throw invalid;
  }

  if (!(await verifyPassword(input.password, account.passwordHash))) throw invalid;

  return openSession(prisma, account);
}

/**
 * Ouvre une session à partir d'une identité déjà **vérifiée** par
 * `SocialVerifier`. Trois cas, dans cet ordre :
 *
 * 1. l'identité est connue — on prend son compte ;
 * 2. l'adresse est connue **et certifiée par le fournisseur** — on rattache la
 *    nouvelle identité au compte existant, pour qu'entrer par Google après
 *    être entré par Apple ne crée pas un doublon ;
 * 3. sinon — nouveau compte.
 *
 * > Important : le cas 2 n'est ouvert qu'aux adresses certifiées. Rattacher sur
 * > une adresse non vérifiée laisserait n'importe qui prendre le contrôle d'un
 * > compte en déclarant son adresse chez un fournisseur complaisant.
 */
export async function signInWithIdentity(
  prisma: PrismaClient,
  identity: VerifiedIdentity,
  /** Ce qu'Apple ne donne qu'à la première autorisation. */
  profile: { firstName?: string | null; lastName?: string | null } = {},
): Promise<IssuedSession> {
  const email = identity.email ? normalizeEmail(identity.email) : null;

  const known = await prisma.identity.findUnique({
    where: { provider_subject: { provider: identity.provider, subject: identity.subject } },
    include: { account: true },
  });

  if (known) {
    const account = await fillMissingProfile(prisma, known.account, profile);
    return openSession(prisma, account);
  }

  // Une adresse non certifiée ne devient jamais l'adresse du compte. Deux
  // raisons, et la seconde n'est pas théorique : elle ne doit pas servir à
  // hériter d'un compte existant, et l'adresse du compte est unique — la
  // revendiquer sur la foi d'un fournisseur qui ne l'a pas vérifiée ferait
  // échouer l'inscription suivante sur une violation de contrainte.
  //
  // Elle reste conservée sur l'identité, qui n'a pas cette contrainte : c'est
  // ce que le fournisseur a dit, et ça peut servir au support.
  const verifiedEmail = email && identity.emailVerified ? email : null;

  const linkable = verifiedEmail
    ? await prisma.account.findUnique({ where: { email: verifiedEmail } })
    : null;

  const account =
    linkable ??
    (await prisma.account.create({
      data: {
        email: verifiedEmail,
        emailVerifiedAt: verifiedEmail ? new Date() : null,
        firstName: profile.firstName?.trim() || null,
        lastName: profile.lastName?.trim() || null,
      },
    }));

  await prisma.identity.create({
    data: {
      accountId: account.id,
      provider: identity.provider,
      subject: identity.subject,
      email,
    },
  });

  return openSession(prisma, await fillMissingProfile(prisma, account, profile));
}

/**
 * Complète les champs restés vides, sans jamais écraser ce qui est déjà là :
 * Apple ne redonne le nom qu'une fois, et l'utilisateur a pu le corriger
 * depuis.
 */
async function fillMissingProfile(
  prisma: PrismaClient,
  account: Account,
  profile: { firstName?: string | null; lastName?: string | null },
): Promise<Account> {
  const firstName = account.firstName ?? profile.firstName?.trim() ?? null;
  const lastName = account.lastName ?? profile.lastName?.trim() ?? null;

  if (firstName === account.firstName && lastName === account.lastName) return account;

  return prisma.account.update({
    where: { id: account.id },
    data: { firstName, lastName },
  });
}

/** Ce que l'API rend d'un compte. Jamais l'empreinte du mot de passe. */
export function serializeAccount(account: Account) {
  return {
    id: account.id,
    email: account.email,
    firstName: account.firstName,
    lastName: account.lastName,
    createdAt: account.createdAt.toISOString(),
  };
}
