import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { connectorByKey } from "../services/connectorCatalog.js";
import { linkDeviceToAccount, visibleToAccount } from "../services/memoOwnership.js";
import { hashDeviceToken } from "../lib/auth.js";
import {
  aggregateTravelStatistics,
  memoStatisticsSelect,
  type TravelStatistics,
} from "../services/travelStatistics.js";
  AVATAR_FILENAME,
  AVATAR_PREFIX,
  avatarMimeType,
} from "../services/avatars.js";
import { serializeProfile, type TripForProfileStats } from "./appSerializers.js";

/** Une photo de profil ne pèse pas plus : l'app la réduit avant de l'envoyer. */
const MAX_AVATAR_BYTES = 5 * 1024 * 1024;

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
  // Ce que la personne dit d'elle-même : un des trois choix, jamais `null` —
  // « je ne préfère pas répondre » est une réponse, pas une absence.
  gender: z.enum(["female", "male", "undisclosed"]).optional(),
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

/**
 * La feuille « Statistiques » : tous les voyages visibles du compte, réduits
 * aux colonnes que l'addition regarde — voir `memoStatisticsSelect`. **Une
 * requête**, et pas une par voyage : la feuille se relit toutes les quelques
 * secondes tant qu'un souvenir est en cours de rédaction.
 */
async function readTravelStatistics(
  context: AppContext,
  accountId: string,
): Promise<TravelStatistics> {
  const memos = await context.prisma.memo.findMany({
    where: visibleToAccount(accountId),
    select: memoStatisticsSelect,
  });
  return aggregateTravelStatistics(memos);
}

/** Ce que `serializeProfile` attend du compte, et rien de plus. */
const profileInclude = {
  cards: { orderBy: [{ isDefault: "desc" as const }, { createdAt: "asc" as const }] },
  connectors: true,
  // Un seul abonnement compte : le vivant. Les résiliés restent en base pour
  // l'historique de facturation, ils n'ont rien à faire à l'écran.
  // **Tout l'historique récent, pas seulement l'abonnement en cours.** Le
  // paywall de retour se déduit d'un abonnement *terminé* : filtrer sur les
  // seuls actifs revenait à ne jamais pouvoir le montrer. Cinq suffisent — au
  // delà, on ne lit plus rien de neuf.
  subscriptions: {
    orderBy: { startedAt: "desc" as const },
    take: 5,
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
    //
    // **`draft` en fait partie.** Une commande qui vient d'être passée depuis
    // le tunnel naît en brouillon — l'encaissement n'existe pas encore — et
    // l'exclure faisait disparaître de « Suivi des commandes » la seule que
    // l'app sache créer : on commandait, et le suivi restait vide.
    //
    // **Filtré sur l'acheteur, pas sur le voyage visible.** Un co-voyageur
    // commande son propre exemplaire, à sa propre adresse, avec sa propre
    // cagnotte : son colis n'a rien à faire dans le suivi de quelqu'un d'autre.
    // C'est `orderedByAccountId` qui dit à qui appartient la commande — la
    // même colonne qui dira quelle cagnotte débiter.
    context.prisma.printOrder.findMany({
      where: {
        status: { in: ["draft", "submitted", "in_production", "shipped"] },
        orderedByAccountId: accountId,
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

  /**
   * Les statistiques du profil, additionnées à la lecture depuis les relevés
   * de la rédaction. Servies à tout compte : c'est **l'app** qui tient la
   * ligne sous clé pour un non-abonné, et elle ne demande la feuille qu'une
   * fois ouverte. Le serveur n'a rien à cacher ici — ce sont les chiffres du
   * voyageur lui-même.
   */
  app.get("/v1/profile/statistics", async (request) =>
    readTravelStatistics(context, accountIdOf(request)),
  );

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
        ...(body.gender !== undefined ? { gender: body.gender } : {}),
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
   * La photo de profil — `multipart/form-data`, un champ `file` en `image/*`.
   *
   * Elle part dans le stockage des médias sous `avatars/`, et le compte ne
   * retient que sa **clé** : l'adresse se calcule à la lecture, voir
   * `services/avatars.ts`. L'ancienne photo est retirée du stockage dans la
   * foulée — personne ne la lira plus. On relit le profil entier en réponse,
   * comme le `PATCH` : c'est ce que l'app garde à l'écran.
   */
  app.post("/v1/profile/avatar", async (request) => {
    const accountId = accountIdOf(request);

    const file = await request.file({ limits: { fileSize: MAX_AVATAR_BYTES } });
    if (!file) throw HttpError.badRequest("Aucun fichier reçu.");

    const buffer = await file.toBuffer();
    if (buffer.byteLength === 0) throw HttpError.badRequest("Le fichier reçu est vide.");

    const mimeType = file.mimetype;
    if (mimeType !== "image/jpeg" && mimeType !== "image/png") {
      throw HttpError.badRequest(
        `Type d'image non supporté : ${mimeType}. Attendu : image/jpeg ou image/png.`,
      );
    }

    // L'extension vient du type, pas du nom envoyé : c'est elle qui dira le
    // type MIME à la lecture (`avatarMimeType`).
    const filename = mimeType === "image/png" ? "avatar.png" : "avatar.jpg";
    const stored = await context.storage.put(AVATAR_PREFIX, filename, buffer, mimeType);

    const previous = await context.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
      select: { avatarStorageKey: true },
    });

    await context.prisma.account.update({
      where: { id: accountId },
      data: { avatarStorageKey: stored.storageKey },
    });

    if (previous.avatarStorageKey) {
      await context.storage.remove([previous.avatarStorageKey]).catch((cause: unknown) => {
        request.log.warn({ cause }, "Ancienne photo de profil non retirée du stockage");
      });
    }

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

/**
 * Sert une photo de profil, **sans session** — `AsyncImage` n'envoie pas
 * d'en-tête, et l'avatar se montre à ceux qui partagent le voyage. La clé est
 * un UUID : le nom est entièrement contraint par `AVATAR_FILENAME`, donc ni
 * `..` ni `/`, et rien à deviner. Mise en cache longue : la clé change à
 * chaque nouvelle photo, l'ancienne adresse n'a plus à être revalidée.
 */
export function registerAvatarRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/avatars/:file", async (request, reply) => {
    const { file } = request.params as { file: string };
    if (!AVATAR_FILENAME.test(file)) throw HttpError.notFound("Photo introuvable.");

    let body: Buffer;
    try {
      body = await context.storage.get(`${AVATAR_PREFIX}/${file}`);
    } catch {
      throw HttpError.notFound("Photo introuvable.");
    }

    return reply
      .header("Cache-Control", "public, max-age=2592000, immutable")
      .type(avatarMimeType(file))
      .send(body);
  });
}
