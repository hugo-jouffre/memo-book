/**
 * Erreur portant un code HTTP. Le gestionnaire d'erreurs global de Fastify la
 * traduit en réponse ; tout le reste (bug, panne d'un fournisseur) devient un
 * 500 dont le détail reste dans les logs.
 *
 * `details` part **à plat** dans le corps, à côté de `error` et `message`
 * (03/10/2026) : un refus qui sait quelque chose d'utile le dit sans second
 * appel — le 429 `daily_credit_exhausted` porte le solde `dailyCredit`, d'où
 * l'app lit l'heure à laquelle la file hors ligne pourra repartir. `error` et
 * `message` gardent le dernier mot : un détail ne les écrase jamais.
 */
export class HttpError extends Error {
  constructor(
    readonly statusCode: number,
    message: string,
    readonly code?: string,
    readonly details?: Readonly<Record<string, unknown>>,
  ) {
    super(message);
    this.name = "HttpError";
  }

  static badRequest(message: string, code = "bad_request"): HttpError {
    return new HttpError(400, message, code);
  }

  // Message neutre : deux identifications cohabitent — l'appareil et le compte
  // — et parler du « token d'appareil » sur une route de compte envoie le
  // lecteur chercher au mauvais endroit.
  static unauthorized(message = "Token manquant ou invalide."): HttpError {
    return new HttpError(401, message, "unauthorized");
  }

  static notFound(message = "Ressource introuvable."): HttpError {
    return new HttpError(404, message, "not_found");
  }

  static conflict(message: string): HttpError {
    return new HttpError(409, message, "conflict");
  }
}
