import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { createMemoFor, visibleToAccount } from "../services/memoOwnership.js";
import {
  serializeGalleryCategory,
  serializeGalleryTrip,
  serializeShowcase,
  serializeTraveller,
  serializeTrip,
  serializeTripStep,
} from "./appSerializers.js";

/**
 * Les trois écrans qui montrent des voyages : l'accueil, un voyage ouvert, et
 * la galerie des carnets de la communauté.
 *
 * Ils tiennent sur **une réponse chacun**. L'accueil de l'app est une seule
 * vue : la découper en trois appels ferait apparaître ses morceaux les uns
 * après les autres, et c'est exactement ce qu'on ne veut pas voir au
 * lancement.
 *
 * Ces routes exigent une **session de compte**, pas un token d'appareil : elles
 * parlent d'une personne, de ses voyages et de ceux où elle est invitée. La
 * galerie ne montre les voyages de personne en particulier, mais son appel à
 * l'action dépend de ce que *celui qui regarde* a déjà ouvert — elle a donc
 * besoin de savoir qui il est.
 */

/**
 * L'identifiant d'un voyage.
 *
 * Il n'est **pas** validé par Zod, et c'est voulu : une chaîne qui n'est pas un
 * UUID faisait remonter un 400 « Requête invalide. » jusqu'à l'écran du voyage,
 * qui l'affichait tel quel. Or du point de vue de l'appelant, un identifiant
 * mal formé et un identifiant inconnu disent la même chose — ce voyage n'existe
 * pas — et c'est déjà ce que cette route répond à quelqu'un qui n'y participe
 * pas. Un seul message, donc, et un seul code.
 */
const idParams = z.object({ id: z.string().min(1).max(64) });

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Ce dont `serializeTrip` a besoin, et rien de plus. */
const tripInclude = {
  members: {
    where: { status: { not: "removed" as const } },
    include: { account: true },
    orderBy: { invitedAt: "asc" as const },
  },
} as const;

/**
 * Ce que les six étapes de la création remplissent, et rien d'autre.
 *
 * Une seule des six est obligatoire : le **titre**, parce qu'un carnet sans
 * titre n'existe pas. Toutes les autres portent un « Passer » dans la maquette,
 * et passer veut dire `null` — pas une valeur inventée. Le rapport image/texte
 * fait exception : il a une valeur d'équilibre en base (50), c'est elle qui
 * s'applique quand on saute l'étape.
 */
const tripDraft = z.object({
  // Le thème narratif, tel qu’il se lit : « Gastronomie », « Tour du monde »,
  // ou la phrase libre de « Autre ». Il part tel quel dans le contexte de
  // l’agent de rédaction, d’où du texte et non une clé.
  theme: z.string().trim().min(1).max(200).nullish(),
  title: z.string().trim().min(1, "le titre est requis").max(200),
  startDate: z.coerce.date().nullish(),
  endDate: z.coerce.date().nullish(),
  // Le rythme des relances, dans les mots de l'écran — « Tous les jours ».
  // Même raison que `theme` : c’est une consigne lue par un agent.
  narrationPace: z.string().trim().min(1).max(100).nullish(),
  photoTextRatio: z.number().int().min(0).max(100).optional(),
});

/**
 * Où en est le voyage, **déduit de ses dates** et jamais demandé à l'app.
 *
 * L'écran de création ne pose pas la question, et il a raison : quelqu'un qui
 * saisit un départ le mois prochain n'a pas à préciser en plus que son voyage
 * est « à venir ». Sans dates, on suppose qu'il commence maintenant — c'est ce
 * que fait quelqu'un qui ouvre l'app le premier soir.
 */
function stageFromDates(startDate: Date | null, endDate: Date | null) {
  const now = new Date();
  if (endDate && endDate < now) return "past" as const;
  if (startDate && startDate > now) return "upcoming" as const;
  return "ongoing" as const;
}

export function registerHomeRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * Tout ce qu'il faut pour dessiner l'accueil.
   *
   * Les voyages arrivent dans **une** liste : c'est `stage` qui les range, pas
   * trois tableaux que le serveur devrait tenir cohérents entre eux. Le tri
   * final est fait côté app, une fois, à la réception.
   */
  app.get("/v1/home", async (request) => {
    const accountId = accountIdOf(request);

    const [account, memos, showcase] = await Promise.all([
      context.prisma.account.findUniqueOrThrow({ where: { id: accountId } }),

      context.prisma.memo.findMany({
        where: visibleToAccount(accountId),
        orderBy: { createdAt: "desc" },
        include: tripInclude,
      }),

      // La carte de découverte : la première active dont la fenêtre est
      // ouverte. `position` tranche entre deux campagnes qui se chevauchent.
      context.prisma.showcase.findFirst({
        where: {
          isActive: true,
          AND: [
            { OR: [{ startsAt: null }, { startsAt: { lte: new Date() } }] },
            { OR: [{ endsAt: null }, { endsAt: { gte: new Date() } }] },
          ],
        },
        orderBy: { position: "asc" },
      }),
    ]);

    return {
      traveller: serializeTraveller(account),
      trips: memos.map(serializeTrip),
      showcase: showcase ? serializeShowcase(showcase) : null,
    };
  });

  /**
   * Un voyage ouvert : sa couverture, la relance de MemoBook, et ses étapes.
   *
   * L'accès passe par `visibleToAccount` : un invité voit le voyage, quelqu'un
   * qui n'y participe pas reçoit un 404 — et non un 403, qui confirmerait
   * l'existence du carnet.
   */
  app.get("/v1/trips/:id", async (request) => {
    const accountId = accountIdOf(request);
    const { id } = idParams.parse(request.params);

    // Postgres refuse de comparer une colonne `uuid` à une chaîne qui n'en est
    // pas une : sans ce garde-fou, la requête lève au lieu de ne rien trouver.
    if (!UUID_PATTERN.test(id)) throw HttpError.notFound("Voyage introuvable.");

    const memo = await context.prisma.memo.findFirst({
      where: { id, ...visibleToAccount(accountId) },
      include: {
        ...tripInclude,
        steps: { orderBy: { number: "asc" } },
      },
    });

    if (!memo) throw HttpError.notFound("Voyage introuvable.");

    const trip = serializeTrip(memo);

    return {
      trip,
      prompt: memo.prompt,
      steps: memo.steps.map((step) => serializeTripStep(step, trip.companions)),
    };
  });

  /**
   * Crée un voyage — la sortie des six étapes de « Créer un voyage ».
   *
   * Elle répond **le code d'accès en plus du voyage**, parce que la dernière
   * étape ne montre que lui : c'est la seule réponse de l'app qui l'expose, et
   * elle l'expose à celui qui vient de créer le carnet.
   *
   * La création se fait à la validation de l'avant-dernière étape, et non au
   * « Commencer ! » de la fin : le code se partage avant que le voyage ne
   * s'ouvre, donc le voyage doit exister avant l'écran qui le partage.
   */
  app.post("/v1/trips", async (request, reply) => {
    const accountId = accountIdOf(request);
    const draft = tripDraft.parse(request.body ?? {});

    if (draft.startDate && draft.endDate && draft.endDate < draft.startDate) {
      throw HttpError.badRequest("La date de fin précède la date de début.");
    }

    const memo = await createMemoFor(context.prisma, accountId, {
      title: draft.title,
      theme: draft.theme ?? null,
      startDate: draft.startDate ?? null,
      endDate: draft.endDate ?? null,
      narrationPace: draft.narrationPace ?? null,
      ...(draft.photoTextRatio === undefined ? {} : { photoTextRatio: draft.photoTextRatio }),
      stage: stageFromDates(draft.startDate ?? null, draft.endDate ?? null),
    });

    return reply.code(201).send({
      trip: serializeTrip({ ...memo, members: [] }),
      accessCode: memo.accessCode,
    });
  });

  /**
   * Corrige un voyage avec les mêmes six champs.
   *
   * Elle existe pour la **flèche de retour** de la création : revenir sur les
   * dates après avoir vu le code d'accès ne doit pas créer un second voyage.
   * Le code, lui, ne bouge jamais — il a peut-être déjà été envoyé à quelqu'un.
   */
  app.patch("/v1/trips/:id", async (request) => {
    const accountId = accountIdOf(request);
    const { id } = idParams.parse(request.params);
    const draft = tripDraft.parse(request.body ?? {});

    if (!UUID_PATTERN.test(id)) throw HttpError.notFound("Voyage introuvable.");

    if (draft.startDate && draft.endDate && draft.endDate < draft.startDate) {
      throw HttpError.badRequest("La date de fin précède la date de début.");
    }

    const existing = await context.prisma.memo.findFirst({
      where: { id, ...visibleToAccount(accountId) },
      select: { id: true },
    });
    if (!existing) throw HttpError.notFound("Voyage introuvable.");

    const memo = await context.prisma.memo.update({
      where: { id },
      data: {
        title: draft.title,
        theme: draft.theme ?? null,
        startDate: draft.startDate ?? null,
        endDate: draft.endDate ?? null,
        narrationPace: draft.narrationPace ?? null,
        ...(draft.photoTextRatio === undefined ? {} : { photoTextRatio: draft.photoTextRatio }),
        stage: stageFromDates(draft.startDate ?? null, draft.endDate ?? null),
      },
      include: tripInclude,
    });

    return { trip: serializeTrip(memo), accessCode: memo.accessCode };
  });

  /**
   * La galerie des carnets de la communauté — l'écran « Exemples de carnets ».
   *
   * **Un seul critère d'entrée** : `memos.isPublicGallery`. Ni le propriétaire,
   * ni le stade, ni la présence d'un rendu ne comptent — un carnet est dans la
   * galerie parce que quelqu'un a coché « Affiché sur la galerie de la
   * communauté », et pour aucune autre raison.
   *
   * Les catégories arrivent dans la même réponse que les carnets, et le
   * filtrage se fait dans l'app : la barre bascule d'une catégorie à l'autre
   * sans aller-retour réseau, et la liste ne peut pas se retrouver en avance
   * sur ses filtres.
   */
  app.get("/v1/gallery", async (request) => {
    const accountId = accountIdOf(request);

    const [categories, memos, resumable] = await Promise.all([
      context.prisma.galleryCategory.findMany({
        where: { isActive: true },
        orderBy: { position: "asc" },
      }),

      context.prisma.memo.findMany({
        where: { isPublicGallery: true },
        // Le voyage le plus récent d'abord. `createdAt` départage les carnets
        // sans date de départ, qui remonteraient sinon dans un ordre changeant.
        orderBy: [{ startDate: "desc" }, { createdAt: "desc" }],
        include: {
          // Les étapes ne servent qu'à leurs pays : c'est ce qui distingue un
          // voyage dans un seul pays (son drapeau) d'un tour du monde (le
          // globe).
          steps: {
            select: { destinationName: true, destinationCountryCode: true },
            orderBy: { number: "asc" },
          },
          categories: { select: { categoryId: true } },
        },
      }),

      // Le carnet que l'appel à l'action propose de reprendre : celui qui est
      // en cours, sinon le prochain voyage prévu. La même règle que
      // `HomeModel.resumableTrip` côté app — le libellé du bouton change avec
      // lui (« Continuer mon voyage » plutôt que « Créer mon voyage »), et deux
      // écrans qui répondraient différemment à la même question seraient un
      // bug qu'on ne verrait qu'en passant de l'un à l'autre.
      context.prisma.memo.findMany({
        where: { ...visibleToAccount(accountId), stage: { in: ["ongoing", "upcoming"] } },
        select: { id: true, stage: true, startDate: true },
      }),
    ]);

    return {
      categories: categories.map(serializeGalleryCategory),
      trips: memos.map(serializeGalleryTrip),
      resumableTripId: resumableTripId(resumable),
    };
  });
}

/**
 * Le voyage qu'on propose de reprendre : le voyage en cours commencé le plus
 * récemment, sinon le départ le plus proche.
 *
 * Le tri se fait ici et non en SQL parce qu'il change de sens d'un stade à
 * l'autre — le plus récent des voyages en cours, le plus proche des voyages à
 * venir. Une requête qui ferait les deux demanderait deux appels.
 */
function resumableTripId(
  memos: { id: string; stage: "ongoing" | "upcoming" | "past"; startDate: Date | null }[],
): string | null {
  const ongoing = memos
    .filter((memo) => memo.stage === "ongoing")
    .sort((a, b) => (b.startDate?.getTime() ?? 0) - (a.startDate?.getTime() ?? 0));

  if (ongoing[0]) return ongoing[0].id;

  const upcoming = memos
    .filter((memo) => memo.stage === "upcoming")
    .sort(
      (a, b) =>
        (a.startDate?.getTime() ?? Number.MAX_SAFE_INTEGER) -
        (b.startDate?.getTime() ?? Number.MAX_SAFE_INTEGER),
    );

  return upcoming[0]?.id ?? null;
}

/**
 * Les carnets montrés sur l'écran de bienvenue, celui qui n'apparaît qu'au
 * premier lancement.
 *
 * **Non authentifiée**, et enregistrée à part pour cette raison : elle
 * s'affiche avant l'entrée dans un compte. Elle ne sert que du contenu
 * éditorial choisi depuis la base, jamais celui d'un utilisateur.
 */
export function registerWelcomeRoutes(app: FastifyInstance, context: AppContext): void {
  app.get("/v1/showcases/welcome", async () => {
    const now = new Date();

    const showcases = await context.prisma.showcase.findMany({
      where: {
        showOnWelcomeScreen: true,
        AND: [
          { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
          { OR: [{ endsAt: null }, { endsAt: { gte: now } }] },
        ],
      },
      orderBy: { position: "asc" },
      take: 10,
    });

    return { showcases: showcases.map(serializeShowcase) };
  });
}
