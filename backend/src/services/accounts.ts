import type { PrismaClient } from "@prisma/client";
import type { AppContext } from "../context.js";
import { generateToken, hashToken, normalizeEmail } from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";

/** Ce que l'app reçoit quand une session s'ouvre. */
export interface AuthenticatedSession {
  userId: string;
  sessionToken: string;
  /** Restauré depuis le serveur : une réinstallation ne repropose pas le
   *  Welcome Screen à quelqu'un qui a déjà un compte. */
  hasSeenOnboarding: boolean;
}

const DAY_IN_MS = 24 * 60 * 60 * 1000;

/**
 * Ouvre une session et renvoie le jeton en clair — la seule fois où il existe
 * ailleurs que dans le trousseau de l'app.
 */
export async function openSession(
  context: AppContext,
  user: { id: string; hasSeenOnboarding: boolean },
  deviceId: string,
): Promise<AuthenticatedSession> {
  const sessionToken = generateToken();

  await context.prisma.session.create({
    data: {
      userId: user.id,
      deviceId,
      tokenHash: hashToken(sessionToken),
      expiresAt: new Date(Date.now() + context.env.SESSION_TTL_DAYS * DAY_IN_MS),
    },
  });

  return {
    userId: user.id,
    sessionToken,
    hasSeenOnboarding: user.hasSeenOnboarding,
  };
}

/**
 * Rattache l'appareil qui vient de s'authentifier au compte.
 *
 * Le premier appareil rattaché devient l'appareil principal : c'est lui qui
 * porte les carnets. Un appareil suivant — une réinstallation, un deuxième
 * téléphone — cède ses carnets au principal avant de s'y relier, plutôt que de
 * les laisser sur une identité que plus personne n'interroge. C'est ce qui rend
 * l'inscription indolore quand on a déjà raconté trois étapes en anonyme.
 *
 * Renvoie l'identifiant de l'appareil principal du compte, qui existe toujours
 * une fois cette fonction passée.
 */
export async function attachDevice(
  prisma: PrismaClient,
  userId: string,
  deviceToken: string | undefined,
): Promise<string> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { primaryDeviceId: true },
  });
  if (!user) throw HttpError.notFound("Compte introuvable.");

  const device = deviceToken
    ? await prisma.device.findUnique({
        where: { tokenHash: hashToken(deviceToken) },
        select: { id: true, userId: true },
      })
    : null;

  // Pas de jeton, ou un jeton inconnu (appareil supprimé côté serveur, jeton
  // d'une autre installation) : la connexion aboutit quand même. Le compte a
  // simplement besoin d'un appareil principal pour porter ses carnets.
  if (!device) return user.primaryDeviceId ?? createPrimaryDevice(prisma, userId);

  if (device.userId && device.userId !== userId) {
    throw HttpError.conflict("Cet appareil est déjà rattaché à un autre compte.");
  }

  if (!user.primaryDeviceId) {
    await prisma.$transaction([
      prisma.device.update({ where: { id: device.id }, data: { userId } }),
      prisma.user.update({ where: { id: userId }, data: { primaryDeviceId: device.id } }),
    ]);
    return device.id;
  }

  if (device.id === user.primaryDeviceId) {
    return user.primaryDeviceId;
  }

  await prisma.$transaction([
    prisma.memo.updateMany({
      where: { deviceId: device.id },
      data: { deviceId: user.primaryDeviceId },
    }),
    prisma.device.update({ where: { id: device.id }, data: { userId } }),
  ]);

  return user.primaryDeviceId;
}

/**
 * Crée l'appareil principal d'un compte qui n'en a pas encore.
 *
 * Son jeton est tiré puis oublié : personne ne le détient, et c'est voulu. Cet
 * appareil n'est pas un téléphone, c'est le porteur des carnets du compte — on
 * ne l'atteint qu'à travers une session.
 */
async function createPrimaryDevice(
  prisma: PrismaClient,
  userId: string,
): Promise<string> {
  const device = await prisma.device.create({
    data: { tokenHash: hashToken(generateToken()), platform: "ios", userId },
    select: { id: true },
  });

  await prisma.user.update({
    where: { id: userId },
    data: { primaryDeviceId: device.id },
  });

  return device.id;
}

/** Cherche un compte par son email, en forme canonique. */
export function findUserByEmail(prisma: PrismaClient, email: string) {
  return prisma.user.findUnique({ where: { email: normalizeEmail(email) } });
}
