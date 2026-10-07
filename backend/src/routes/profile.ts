import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { connectorByKey } from "../services/connectorCatalog.js";
import { findShippingCountry } from "../services/shippingCountries.js";
import { linkDeviceToAccount, visibleToAccount } from "../services/memoOwnership.js";
import { hashDeviceToken, hashSessionToken, parseBearerToken } from "../lib/auth.js";
import { hashPassword, verifyPassword } from "../lib/password.js";
import { pushCancellationToSheet } from "../services/statsExport.js";
import { LIVING_SUBSCRIPTION_STATUSES } from "../services/subscriptions.js";
import {
  aggregateTravelStatistics,
  memoStatisticsSelect,
  type TravelStatistics,
} from "../services/travelStatistics.js";
import {
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
 * Tout arrive en une réponse — identité, adresse, cartes,
 * connecteurs, abonnement, commandes en cours — parce que l'écran les affiche
 * ensemble. Sept appels feraient apparaître ses lignes une à une.
 */

/**
 * Un champ absent n'est pas touché ; un champ à `null` est effacé. « Pas de
 * téléphone » et « un téléphone vide » ne sont pas la même chose, et c'est la
 * sémantique JSON qui fait la différence — pas une chaîne vide.
 */
const nullableText = (max: number) => z.string().trim().max(max).nullable().optional();

/**
 * Le pays d'une adresse : un pays **où l'imprimeur livre**, ou rien.
 *
 * L'app envoie le code ISO depuis qu'elle le choisit dans la liste servie avec
 * le profil ; un nom (« France ») est encore accepté et ramené au code, parce
 * qu'une app d'avant le 18/09/2026 saisissait le pays en texte libre. Un pays
 * hors liste est refusé **ici**, et non à la commande : le profil est l'amorce
 * de l'étape 2, et une amorce que l'étape 2 refuserait ne sert à rien. Une
 * `HttpError` plutôt qu'un refus de `zod`, pour que l'app reçoive la phrase et
 * non « Requête invalide ».
 */
function shippingCountryCode(value: string | null | undefined): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null || value === "") return null;

  const country = findShippingCountry(value);
  if (!country) {
    throw HttpError.badRequest("Ce pays n'est pas encore livré. Choisis-en un dans la liste.");
  }
  return country.code;
}

/**
 * Une date de naissance : un **jour**, `AAAA-MM-JJ`, ni dans le futur ni avant
 * 1900. Le jour et non l'instant, parce qu'un instant se relit dans un autre
 * fuseau — et une naissance le 12 mai à minuit UTC devenait le 11 mai à New
 * York. `null` l'efface, comme partout sur cette route.
 */
const birthDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "La date de naissance s'écrit AAAA-MM-JJ.")
  .refine((value) => {
    const date = new Date(`${value}T00:00:00.000Z`);
    return (
      !Number.isNaN(date.getTime()) &&
      date.toISOString().slice(0, 10) === value &&
      date.getUTCFullYear() >= 1900 &&
      date.getTime() <= Date.now()
    );
  }, "Cette date de naissance n'existe pas.")
  .nullable()
  .optional();

const updateBody = z.object({
  firstName: nullableText(100),
  lastName: nullableText(100),
  phoneNumber: nullableText(40),
  birthDate,
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
 * La raison de la résiliation, facultative.
 *
 * Facultative parce qu'elle est un sondage : l'app grise son bouton tant que
 * rien n'est coché, mais un client plus ancien — ou un rejeu — ne doit pas se
 * voir refuser une résiliation pour une question de statistique.
 */
const cancelSubscriptionBody = z.object({
  reason: z.string().trim().min(1).max(60).optional(),
});

/**
 * Changer son mot de passe : l'actuel pour preuve, le nouveau aux mêmes règles
 * que l'inscription (`PasswordRule`, dans `MemoBookCore`).
 */
const changePasswordBody = z.object({
  currentPassword: z.string().min(1),
  newPassword: z
    .string()
    .min(8)
    .refine((value) => /\p{L}/u.test(value) && /\d/.test(value), {
      message: "Le mot de passe doit contenir au moins une lettre et un chiffre.",
    }),
});

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
  // **Tout l'historique récent, pas seulement l'abonnement en cours.** Le
  // paywall de retour se déduit d'un abonnement *terminé* : filtrer sur les
  // seuls actifs revenait à ne jamais pouvoir le montrer. Cinq suffisent — au
  // delà, on ne lit plus rien de neuf.
  subscriptions: {
    orderBy: { startedAt: "desc" as const },
    take: 5,
    // Le voyage qu'il finance, pour l'écrire sur les feuilles de l'abonnement
    // (T71). `null` tant qu'aucun abonnement n'est rattaché.
    include: { memo: { select: { title: true, destinationCity: true } } },
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
export async function readProfile(context: AppContext, accountId: string) {
  const [account, orders, trips] = await Promise.all([
    context.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
      include: profileInclude,
    }),

    // Le suivi des commandes : celles en cours d'acheminement, **et celles
    // dont le paiement a été abandonné** (T232, Hugo 06/10/2026) — étiquette
    // « paiement abandonné, commande non finalisée » et CTA « Finaliser ma
    // commande ». Les secondes se trient plus bas (`trackedOrders`) ; on lit
    // ici tout ce qui pourrait en être : trente jours d'historique, plus ce qui
    // est encore en route quel que soit son âge.
    //
    // **Filtré sur l'acheteur, pas sur le voyage visible.** Un co-voyageur
    // commande son propre exemplaire, à sa propre adresse : son colis n'a rien
    // à faire dans le suivi de quelqu'un d'autre. C'est `orderedByAccountId`
    // qui dit à qui appartient la commande.
    context.prisma.printOrder.findMany({
      where: {
        orderedByAccountId: accountId,
        OR: [
          { status: { in: [...IN_PROGRESS_STATUSES] } },
          { createdAt: { gte: new Date(Date.now() - ABANDONED_ORDER_SHOWN_DAYS * 24 * 3_600_000) } },
        ],
      },
      orderBy: { createdAt: "desc" },
      include: { memo: { select: { coverPhotoUrl: true, title: true } } },
    }),

    profileTrips(context, accountId),
  ]);

  return serializeProfile(account, trackedOrders(orders), trips);
}

/** Ce qui est payé et pas encore arrivé. */
const IN_PROGRESS_STATUSES = ["submitted", "in_production", "shipped"] as const;

/**
 * Combien de temps une commande abandonnée reste dans le suivi. Au-delà, ce
 * n'est plus une commande qu'on a oublié de finir, c'est une idée qu'on a eue.
 */
const ABANDONED_ORDER_SHOWN_DAYS = 30;

/**
 * Ce que le suivi montre : les commandes en route, et **la dernière commande
 * de chaque voyage si elle n'a jamais été payée**.
 *
 * Jamais payée : un brouillon, ou une commande fermée sans paiement — par le
 * ménage des 24 h, une intention annulée, l'app. Une commande remboursée a été
 * payée : elle n'en est pas. **La dernière seulement** : changer d'adresse au
 * milieu du tunnel ferme la commande précédente et en ouvre une neuve, et la
 * première n'est pas « abandonnée » — elle est remplacée. Et une commande payée
 * après l'abandon, sur le même voyage, le règle.
 */
function trackedOrders<T extends { memoId: string; status: string; submittedAt: Date | null; createdAt: Date }>(
  orders: T[],
): T[] {
  const latestByTrip = new Map<string, T>();
  for (const order of orders) {
    const known = latestByTrip.get(order.memoId);
    if (!known || order.createdAt > known.createdAt) latestByTrip.set(order.memoId, order);
  }

  return orders.filter((order) => {
    if ((IN_PROGRESS_STATUSES as readonly string[]).includes(order.status)) return true;
    const unpaid = order.status === "draft" || (order.status === "cancelled" && order.submittedAt === null);
    return unpaid && latestByTrip.get(order.memoId) === order;
  });
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

    // L'adresse **e-mail** n'est pas modifiable ici : elle appartient au compte
    // Apple ou Google quand la session vient de l'un des deux, et la changer de
    // ce côté ne ferait que la désaccorder de celle avec laquelle on se
    // reconnecte. C'est aussi la règle appliquée par l'app. L'adresse
    // **postale**, elle, se corrige librement : c'est là que part le carnet.

    await context.prisma.account.update({
      where: { id: accountId },
      data: {
        firstName: orNull(body.firstName),
        lastName: orNull(body.lastName),
        phoneNumber: orNull(body.phoneNumber),
        ...(body.birthDate !== undefined
          ? { birthDate: body.birthDate === null ? null : new Date(`${body.birthDate}T00:00:00.000Z`) }
          : {}),
        ...(body.gender !== undefined ? { gender: body.gender } : {}),
        ...(body.wantsNewsletter !== undefined
          ? { wantsNewsletter: body.wantsNewsletter }
          : {}),
        ...(body.address
          ? {
              addressLine1: orNull(body.address.street),
              addressPostalCode: orNull(body.address.postalCode),
              addressCity: orNull(body.address.city),
              addressCountry: shippingCountryCode(body.address.country),
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
   * Retire la photo de profil : le rond revient aux initiales (Hugo,
   * 29/09/2026). L'objet part du stockage dans la foulée — personne ne le
   * lira plus —, et la réponse est le profil relu, comme après un envoi.
   */
  app.delete("/v1/profile/avatar", async (request) => {
    const accountId = accountIdOf(request);

    const previous = await context.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
      select: { avatarStorageKey: true },
    });

    await context.prisma.account.update({
      where: { id: accountId },
      data: { avatarStorageKey: null, avatarUrl: null },
    });

    if (previous.avatarStorageKey) {
      await context.storage.remove([previous.avatarStorageKey]).catch((cause: unknown) => {
        request.log.warn({ cause }, "Photo de profil non retirée du stockage");
      });
    }

    return readProfile(context, accountId);
  });

  /**
   * Change le mot de passe du compte (Hugo, 29/09/2026).
   *
   * Trois refus, chacun avec son code pour que la feuille dise la bonne
   * phrase sous le bon champ : `no_password` (409) pour un compte entré par
   * Apple ou Google seul, `wrong_password` (400) quand l'actuel ne colle pas,
   * `same_password` (400) quand le nouveau est l'ancien. Les autres sessions
   * du compte sont fermées — un mot de passe qu'on change est peut-être un mot
   * de passe qu'on croit compromis —, la sienne reste ouverte.
   */
  app.post("/v1/profile/password", async (request, reply) => {
    const accountId = accountIdOf(request);
    const body = changePasswordBody.parse(request.body ?? {});

    const account = await context.prisma.account.findUniqueOrThrow({
      where: { id: accountId },
      select: { passwordHash: true },
    });
    if (!account.passwordHash) {
      throw new HttpError(
        409,
        "Ce compte s’ouvre avec Apple ou Google : il n’a pas de mot de passe à modifier.",
        "no_password",
      );
    }

    if (!(await verifyPassword(body.currentPassword, account.passwordHash))) {
      throw HttpError.badRequest(
        "Mot de passe incorrect. Vérifie ton mot de passe et réessaie.",
        "wrong_password",
      );
    }

    if (body.currentPassword === body.newPassword) {
      throw HttpError.badRequest(
        "Ton nouveau mot de passe doit être différent de l’ancien.",
        "same_password",
      );
    }

    const token = parseBearerToken(request.headers.authorization);
    await context.prisma.$transaction([
      context.prisma.account.update({
        where: { id: accountId },
        data: { passwordHash: await hashPassword(body.newPassword) },
      }),
      context.prisma.session.deleteMany({
        where: {
          accountId,
          ...(token ? { NOT: { tokenHash: hashSessionToken(token) } } : {}),
        },
      }),
    ]);

    return reply.code(204).send();
  });

  /**
   * Résilie l'abonnement — **et ça tient**.
   *
   * Jusqu'au 19/09/2026, les trois feuilles de résiliation ne touchaient que
   * l'écran : `ProfileModel.cancelSubscription` posait `isActive` à faux dans
   * sa copie locale et rien ne partait. Le prochain chargement du profil
   * relisait la ligne `subscriptions` du serveur, toujours active, et la
   * personne se retrouvait abonnée — après avoir confirmé trois fois.
   *
   * **`cancelled`, pas `expired`.** Les deux ferment l'abonnement et les deux
   * gardent la période réglée (`PAID_THROUGH_SUBSCRIPTION_STATUSES`,
   * `subscriptions.ts`), mais ils ne disent pas la même chose : `expired` est
   * une période qui finit sans renouvellement, `cancelled` est quelqu'un qui
   * s'en va. La distinction se lit dans l'historique, et c'est elle qui fera
   * voir le paywall de retour.
   *
   * **Le mois payé n'est pas rendu.** `renewsAt` reste tel quel : c'est lui
   * qui porte le sursis, côté app comme côté crédit du jour. Résilier le 3 ne
   * rembourse pas la fin du mois, et ne referme donc pas l'illimité non plus
   * (Hugo, 16/09/2026, redit le 03/10/2026).
   *
   * **Idempotent.** Résilier deux fois — un double tapotis, une requête
   * rejouée — n'est pas une erreur : la seconde ne trouve plus d'abonnement
   * vivant et rend le profil tel quel.
   *
   * 🚨 **Un abonnement StoreKit ne se résilie pas ici** (01/10/2026). Apple ne
   * laisse aucune app résilier à la place de son client : c'est l'app qui
   * ouvre ensuite la feuille de gestion des abonnements d'iOS, et c'est la
   * notification d'Apple (`AUTO_RENEW_DISABLED`) qui fermera la ligne. La
   * fermer d'ici ferait croire l'abonnement arrêté pendant qu'Apple continue de
   * prélever. Pour lui, cette route n'enregistre que **la raison**.
   */
  app.post("/v1/profile/subscription/cancel", async (request) => {
    const accountId = accountIdOf(request);
    const { reason } = cancelSubscriptionBody.parse(request.body ?? {});
    const living = LIVING_SUBSCRIPTION_STATUSES;

    const [{ count: storeKit }, { count: others }] = await Promise.all([
      context.prisma.subscription.updateMany({
        where: { accountId, provider: "storekit", status: { in: [...living] } },
        data: reason === undefined ? {} : { cancellationReason: reason },
      }),
      context.prisma.subscription.updateMany({
        where: { accountId, provider: { not: "storekit" }, status: { in: [...living] } },
        data: {
          status: "cancelled",
          cancelledAt: new Date(),
          ...(reason === undefined ? {} : { cancellationReason: reason }),
        },
      }),
    ]);
    const count = storeKit + others;

    // La raison part aussi dans la feuille de bord (T72) — sans attendre, et
    // sans faire échouer la résiliation si la feuille ne répond pas.
    void pushCancellationToSheet(context, {
      accountId,
      reason: reason ?? null,
      hadActiveSubscription: count > 0,
    });

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
