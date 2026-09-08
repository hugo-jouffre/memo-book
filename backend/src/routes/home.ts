import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import {
  serializeShowcase,
  serializeTraveller,
  serializeTrip,
  serializeTripStep,
} from "./appSerializers.js";

/**
 * Les deux écrans qui montrent des voyages : l'accueil, et un voyage ouvert.
 *
 * Ils tiennent sur **une réponse chacun**. L'accueil de l'app est une seule
 * vue : la découper en trois appels ferait apparaître ses morceaux les uns
 * après les autres, et c'est exactement ce qu'on ne veut pas voir au
 * lancement.
 *
 * Ces routes exigent une **session de compte**, pas un token d'appareil : elles
 * parlent d'une personne, de ses voyages et de ceux où elle est invitée.
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
