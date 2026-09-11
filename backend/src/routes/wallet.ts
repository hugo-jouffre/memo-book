import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { accountIdOf } from "../plugins/auth.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { serializeWallet } from "./appSerializers.js";

/**
 * La cagnotte : ce qu'il y a dessus, d'où ça vient, et ce que le carnet
 * coûtera.
 *
 * **Elle appartient au compte, pas au voyage.** Deux co-voyageurs ont chacun la
 * leur, et c'est la même somme qu'on lit dans le profil et dans les paramètres
 * d'un voyage — d'où une seule route, et un `tripId` facultatif qui ne dit pas
 * *quelle* cagnotte mais **quel carnet on finance**.
 *
 * Le solde ne se recalcule pas ici : `accounts.walletBalanceCents` est le cache
 * tenu à jour dans la même transaction que chaque écriture, et
 * `wallet_entries.balanceAfterCents` permet de vérifier qu'il n'a pas dérivé.
 * Sommer le registre à chaque affichage coûterait une agrégation sur tout
 * l'historique pour une valeur déjà connue.
 */

const query = z.object({ tripId: z.string().uuid().optional() });

/**
 * Combien d'écritures l'historique rend.
 *
 * Cinquante : l'écran les affiche toutes d'un bloc, sans pagination — la
 * maquette n'en dessine pas — et cinquante contributions représentent déjà un
 * carnet très entouré. Au-delà, il faudra paginer, et ce sera un vrai sujet
 * d'écran avant d'être un sujet de route.
 */
const HISTORY_LIMIT = 50;

export function registerWalletRoutes(app: FastifyInstance, context: AppContext) {
  app.get("/v1/wallet", async (request) => {
    const { tripId } = query.parse(request.query);
    const accountId = accountIdOf(request);

    const [account, entries, trip] = await Promise.all([
      context.prisma.account.findUnique({
        where: { id: accountId },
        select: { walletBalanceCents: true },
      }),
      context.prisma.walletEntry.findMany({
        where: { accountId },
        orderBy: { createdAt: "desc" },
        take: HISTORY_LIMIT,
        select: { id: true, amountCents: true, kind: true, label: true, createdAt: true },
      }),
      // Le voyage n'est lu que pour l'estimation. Un identifiant qui ne
      // correspond à rien de visible ne fait pas échouer la route : la cagnotte
      // existe indépendamment du carnet, et l'écran s'affiche sans estimation
      // plutôt que pas du tout.
      tripId
        ? context.prisma.memo.findFirst({
            where: { id: tripId, ...visibleToAccount(accountId) },
            select: {
              title: true,
              destinationCity: true,
              targetPageCount: true,
              pageCount: true,
            },
          })
        : Promise.resolve(null),
    ]);

    return serializeWallet(account?.walletBalanceCents ?? 0, entries, trip);
  });
}
