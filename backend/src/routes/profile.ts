import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { connectorByKey } from "../services/connectorCatalog.js";
import { linkDeviceToAccount, visibleToAccount } from "../services/memoOwnership.js";
import { hashDeviceToken } from "../lib/auth.js";
import { serializeProfile, type TripForProfileStats } from "./appSerializers.js";

/**
 * L'écran de profil : ce qu'il montre, et ce qu'on y change.
 *
 * Tout arrive en une réponse — identité, adresse, cagnotte, cartes,
 * connecteurs, abonnement, commandes en cours — parce que l'écran les affiche
 * ensemble. Sept appels feraient apparaître ses lignes une à une.
 */

/**
 * Un champ absent n'est pas touché ; un champ à `null` est effacé. « Pas de
 * téléphone » et « un téléphone vide » ne sont pas la même chose, et c'est la
 * sémantique JSON qui fait la différence — pas une chaîne vide.
 */
const nullableText = (max: number) => z.string().trim().max(max).nullable().optional();

const updateBody = z.object({
  firstName: nullableText(100),
  lastName: nullableText(100),
  phoneNumber: nullableText(40),
  wantsNewsletter: z.boolean().optional(),
  address: z
    .object({
      street: nullableText(200),
      postalCode: nullableText(20),
      city: nullableText(100),
      country: nullableText(100),
    })
    .optional(),
});

const connectorBody = z.object({ isEnabled: z.boolean() });
const connectorParams = z.object({ key: z.string().min(1).max(64) });
const linkDeviceBody = z.object({ deviceToken: z.string().min(1) });

/**
 * Les voyages du compte, réduits à ce que la carte de chiffres du profil
 * regarde : combien il y en a, et lequel est en cours. Rien de plus — c'est un
 * comptage, pas une seconde liste d'accueil.
 */
function profileTrips(context: AppContext, accountId: string): Promise<TripForProfileStats[]> {
  return context.prisma.memo.findMany({
    where: visibleToAccount(accountId),
    select: { id: true, stage: true, startDate: true, endDate: true },
  });
}

/** Ce que `serializeProfile` attend du compte, et rien de plus. */
const profileInclude = {
  cards: { orderBy: [{ isDefault: "desc" as const }, { createdAt: "asc" as const }] },
  connectors: true,
  // Un seul abonnement compte : le vivant. Les résiliés restent en base pour
  // l'historique de facturation, ils n'ont rien à faire à l'écran.
  subscriptions: {
    where: { status: { in: ["active" as const, "trialing" as const, "past_due" as const] } },
    orderBy: { startedAt: "desc" as const },
    take: 1,
  },
  identities: { orderBy: { createdAt: "asc" as const }, take: 1 },
};

/**
 * Le profil entier, tel que les deux routes le rendent.
 *
 * **Un seul chemin de lecture, appelé aussi après une écriture.** La réponse
 * d'un `PATCH` est ce que l'app garde à l'écran : si elle ne portait qu'une
 * partie du profil — ce qui était le cas des commandes et l'aurait été des
 * chiffres — corriger un numéro de téléphone effacerait le reste de la page.
 */
async function readProfile(context: AppContext, accountId: string) {
  const [account, orders, trips] = await Promise.all([
    context.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
      include: profileInclude,
    }),

    // Les commandes en cours d'acheminement, et elles seules : une commande
    // livrée il y a six mois n'a plus rien à suivre.
    context.prisma.printOrder.findMany({
      where: {
        status: { in: ["submitted", "in_production", "shipped"] },
        memo: visibleToAccount(accountId),
      },
      orderBy: { createdAt: "desc" },
      include: { memo: { select: { coverPhotoUrl: true } } },
    }),

    profileTrips(context, accountId),
  ]);

  return serializeProfile(account, orders, trips);
}

/** Une chaîne vidée redevient `null` : la base ne stocke pas de champ « présent mais vide ». */
function orNull(value: string | null | undefined): string | null | undefined {
  if (value === undefined) return undefined;
  return value === null || value === "" ? null : value;
}

export function registerProfileRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/profile", async (request) => readProfile(context, accountIdOf(request)));

  app.patch("/v1/profile", async (request) => {
    const accountId = accountIdOf(request);
    const body = updateBody.parse(request.body ?? {});

    // L'adresse n'est pas modifiable ici : elle appartient au compte Apple ou
    // Google quand la session vient de l'un des deux, et la changer de ce côté
    // ne ferait que la désaccorder de celle avec laquelle on se reconnecte.
    // C'est aussi la règle appliquée par l'app.

    await context.prisma.account.update({
      where: { id: accountId },
      data: {
        firstName: orNull(body.firstName),
        lastName: orNull(body.lastName),
        phoneNumber: orNull(body.phoneNumber),
        ...(body.wantsNewsletter !== undefined
          ? { wantsNewsletter: body.wantsNewsletter }
          : {}),
        ...(body.address
          ? {
              addressLine1: orNull(body.address.street),
              addressPostalCode: orNull(body.address.postalCode),
              addressCity: orNull(body.address.city),
              addressCountry: orNull(body.address.country),
            }
          : {}),
      },
    });

    // On relit par le **même chemin** que le `GET` : la réponse d'un `PATCH`
    // est ce que l'app garde à l'écran, et un profil amputé de ses commandes ou
    // de ses chiffres les effacerait de la page à chaque correction.
    return readProfile(context, accountId);
  });

  /**
   * Branche ou débranche un connecteur.
   *
   * Ne fait qu'enregistrer l'intention : aucun jeton d'accès n'est délivré ici.
   * Le jour où un connecteur ira vraiment chercher des données, c'est un
   * échange OAuth complet qu'il faudra, et `accessToken` devra être chiffré au
   * repos avant d'accueillir quoi que ce soit.
   */
  app.put("/v1/profile/connectors/:key", async (request) => {
    const accountId = accountIdOf(request);
    const { key } = connectorParams.parse(request.params);
    const body = connectorBody.parse(request.body ?? {});

    if (!connectorByKey(key)) {
      throw HttpError.badRequest(`Connecteur inconnu : ${key}.`);
    }

    await context.prisma.accountConnector.upsert({
      where: { accountId_connectorKey: { accountId, connectorKey: key } },
      create: {
        accountId,
        connectorKey: key,
        isEnabled: body.isEnabled,
        connectedAt: body.isEnabled ? new Date() : null,
      },
      update: {
        isEnabled: body.isEnabled,
        ...(body.isEnabled ? { connectedAt: new Date() } : {}),
      },
    });

    return { key, isEnabled: body.isEnabled };
  });

  /**
   * Rattache l'appareil courant au compte connecté.
   *
   * Il n'y a plus de carnets à réclamer au passage : un carnet naît avec son
   * propriétaire, et l'appareil n'en possède aucun. Ce lien dit désormais une
   * seule chose — sur quelles installations ce compte est ouvert — et c'est ce
   * qui les fait disparaître avec lui.
   *
   * Deux jetons dans la même requête, et c'est voulu : celui du compte dans
   * l'en-tête prouve qui reçoit, celui de l'appareil dans le corps prouve ce
   * qui est rattaché. Un seul des deux ne suffirait à rien démontrer.
   */
  app.post("/v1/profile/link-device", async (request) => {
    const accountId = accountIdOf(request);
    const { deviceToken } = linkDeviceBody.parse(request.body ?? {});

    const device = await context.prisma.device.findUnique({
      where: { tokenHash: hashDeviceToken(deviceToken) },
      select: { id: true, accountId: true },
    });

    if (!device) throw HttpError.notFound("Appareil inconnu.");

    if (device.accountId && device.accountId !== accountId) {
      // Un appareil déjà rattaché ailleurs ne change pas de main sur simple
      // demande : ce serait le moyen de s'approprier les carnets de quelqu'un
      // à qui on a emprunté son téléphone.
      throw HttpError.conflict("Cet appareil est déjà rattaché à un autre compte.");
    }

    await linkDeviceToAccount(context.prisma, device.id, accountId);

    return { deviceId: device.id };
  });
}
