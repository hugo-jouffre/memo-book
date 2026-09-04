/**
 * Erreur portant un code HTTP. Le gestionnaire d'erreurs global de Fastify la
 * traduit en réponse ; tout le reste (bug, panne d'un fournisseur) devient un
 * 500 dont le détail reste dans les logs.
 */
export class HttpError extends Error {
  constructor(
    readonly statusCode: number,
    message: string,
    readonly code?: string,
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
