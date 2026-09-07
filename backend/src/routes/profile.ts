import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { connectorByKey } from "../services/connectorCatalog.js";
import { linkDeviceToAccount, visibleToAccount } from "../services/memoOwnership.js";
import { hashDeviceToken } from "../lib/auth.js";
import { serializeProfile } from "./appSerializers.js";

/**
 * L'écran de profil : ce qu'il montre, et ce qu'on y change.
 *
 * Tout arrive en une réponse — identité, adresse, cagnotte, cartes,
 * connecteurs, abonnement, commandes en cours — parce que l'écran les affiche
 * ensemble. Sept appels feraient apparaître ses lignes une à une.
 */

function accountIdOf(request: FastifyRequest): string {
  if (!request.accountId) throw HttpError.unauthorized();
  return request.accountId;
}

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

/** Une chaîne vidée redevient `null` : la base ne stocke pas de champ « présent mais vide ». */
function orNull(value: string | null | undefined): string | null | undefined {
  if (value === undefined) return undefined;
  return value === null || value === "" ? null : value;
}

export function registerProfileRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/profile", async (request) => {
    const accountId = accountIdOf(request);

    const [account, orders] = await Promise.all([
      context.prisma.account.findUniqueOrThrow({
        where: { id: accountId },
        include: {
          cards: { orderBy: [{ isDefault: "desc" }, { createdAt: "asc" }] },
          connectors: true,
          // Un seul abonnement compte : le vivant. Les résiliés restent en base
          // pour l'historique de facturation, ils n'ont rien à faire à l'écran.
          subscriptions: {
            where: { status: { in: ["active", "trialing", "past_due"] } },
            orderBy: { startedAt: "desc" },
            take: 1,
          },
          identities: { orderBy: { createdAt: "asc" }, take: 1 },
        },
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
    ]);

    return serializeProfile(account, orders);
  });

  app.patch("/v1/profile", async (request) => {
    const accountId = accountIdOf(request);
    const body = updateBody.parse(request.body ?? {});

    // L'adresse n'est pas modifiable ici : elle appartient au compte Apple ou
    // Google quand la session vient de l'un des deux, et la changer de ce côté
    // ne ferait que la désaccorder de celle avec laquelle on se reconnecte.
    // C'est aussi la règle appliquée par l'app.

    const account = await context.prisma.account.update({
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
      include: {
        cards: { orderBy: [{ isDefault: "desc" }, { createdAt: "asc" }] },
        connectors: true,
        subscriptions: {
          where: { status: { in: ["active", "trialing", "past_due"] } },
          orderBy: { startedAt: "desc" },
          take: 1,
        },
        identities: { orderBy: { createdAt: "asc" }, take: 1 },
      },
    });

    return serializeProfile(account, []);
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
   * Rattache l'appareil courant au compte connecté, et lui transfère les
   * carnets qu'il portait seul.
   *
   * Sans cette route, quelqu'un qui a raconté trois étapes avant de se créer un
   * compte les perdrait de vue au moment même où il s'inscrit. L'app l'appelle
   * juste après une connexion réussie, avec son token d'appareil.
   *
   * Deux jetons dans la même requête, et c'est voulu : celui du compte dans
   * l'en-tête prouve qui reçoit, celui de l'appareil dans le corps prouve ce
   * qui est donné. Un seul des deux ne suffirait à rien démontrer.
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

    const { claimed } = await linkDeviceToAccount(context.prisma, device.id, accountId);

    return { deviceId: device.id, claimedMemos: claimed };
  });
}
