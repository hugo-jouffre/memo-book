import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { accountIdOf } from "../plugins/auth.js";
import { deleteAccountAndData } from "../services/deletion.js";

/**
 * Le compte lui-même, par opposition au profil qui n'en est que l'écran.
 */
export function registerAccountRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * Supprime le compte de l'appelant et **tout** ce qui est à lui : carnets,
   * souvenirs, médias, commandes, cagnotte, cartes, abonnements, connecteurs,
   * appareils, avis, sessions et identités.
   *
   * Définitif, immédiat, et sans autre confirmation que celle demandée dans
   * l'app : c'est la règle produit, et c'est aussi ce qu'un magasin
   * d'applications attend d'une app qui laisse ouvrir un compte.
   *
   * Les carnets partagés dont il est propriétaire partent aussi, invités
   * compris. Ceux où il n'était qu'invité restent : seule sa participation
   * disparaît.
   *
   * 204 : la session qui a servi à appeler n'existe plus au moment de la
   * réponse, il n'y a donc rien à renvoyer.
   */
  app.delete("/v1/accounts/me", async (request, reply) => {
    await deleteAccountAndData(context, accountIdOf(request));
    return reply.code(204).send();
  });
}
