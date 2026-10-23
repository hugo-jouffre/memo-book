import type { AppContext } from "../context.js";

/**
 * **Une trace laissée chez un prestataire, à effacer** — ce que nos tables ne
 * contiennent plus mais qui vit encore ailleurs, une fois un compte, un voyage
 * ou un souvenir supprimé (`services/deletion.ts`) :
 *
 *  - `stripe` : le client Stripe du compte — son adresse, son nom, ses cartes ;
 *  - `webflow` : la copie publique d'une photo sur le CDN de memo-book.com ;
 *  - `apitemplate` : le PDF d'un carnet, hébergé par APITemplate ;
 *  - `s3` : nos propres fichiers, quand leur suppression immédiate a échoué.
 *
 * **Une trace par job**, et pas une liste par compte : pg-boss rejoue un job
 * en échec, et rejouer une liste referait chez Stripe ce qui y a déjà réussi.
 * Chaque effacement se rejoue sans risque (un objet déjà absent compte comme
 * effacé), mais une panne chez l'un ne doit pas retenir les autres.
 *
 * La charge utile ne porte que des identifiants de prestataire — aucune
 * adresse, aucun nom : elle reste dans la table de pg-boss après coup.
 */
export type EraseTraceJob =
  | { provider: "stripe"; customerId: string }
  | { provider: "webflow"; assetId: string }
  | { provider: "apitemplate"; transactionId: string }
  | { provider: "s3"; storageKeys: string[] };

/**
 * Efface une trace. **Lève en cas d'échec** : c'est ce qui fait rejouer le job
 * par pg-boss, avec l'attente qui s'allonge (`RETRY_POLICIES` dans
 * `queue.ts`). Le journal garde chaque échec ; le dernier reste dans la table
 * de pg-boss, en `failed`.
 */
export async function eraseTrace(context: AppContext, job: EraseTraceJob): Promise<void> {
  try {
    switch (job.provider) {
      case "stripe":
        await context.payments.deleteCustomer(job.customerId);
        break;
      case "webflow":
        await context.publisher.unpublish(job.assetId);
        break;
      case "apitemplate":
        await context.renderer.discard(job.transactionId);
        break;
      case "s3":
        await context.storage.remove(job.storageKeys);
        break;
    }
  } catch (cause) {
    context.logger.error({ err: cause, ...job }, "Trace chez un prestataire pas encore effacée");
    throw cause;
  }
}
