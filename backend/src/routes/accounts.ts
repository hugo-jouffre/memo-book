import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { accountIdOf } from "../plugins/auth.js";
import { requestDataExport } from "../services/dataExport.js";
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

  /**
   * « Exporter mes données » : envoie à l'adresse du compte le lien de la page
   * où télécharger toutes ses données, valable sept jours. Rien n'est préparé
   * ici — l'archive se compose à l'ouverture du lien, voir
   * `services/dataExport.ts`.
   *
   * 202 : la demande est acceptée, la suite se passe dans la boîte mail. Une
   * demande qui en suit une autre de moins de cinq minutes n'envoie rien et le
   * dit (`alreadyRequested`). 409 `no_email` sans adresse où écrire, 503
   * `email_unavailable` quand Resend refuse l'envoi.
   */
  app.post("/v1/accounts/me/export", async (request, reply) => {
    const receipt = await requestDataExport(context, accountIdOf(request));
    return reply.code(202).send({
      email: receipt.email,
      requestedAt: receipt.requestedAt.toISOString(),
      expiresAt: receipt.expiresAt.toISOString(),
      alreadyRequested: receipt.alreadyRequested,
    });
  });
}
