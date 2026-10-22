import type { IncomingHttpHeaders } from "node:http";

/**
 * **Le téléphone d'où vient l'appel** (lot B5, 22/10/2026) — `ios` ou
 * `android`.
 *
 * L'app Android envoie `X-App-Platform: android` sur chaque appel ; l'app iOS
 * ne l'envoie pas, et les builds iOS en circulation ne l'enverront jamais :
 * **absent, c'est un iPhone**. Toute autre valeur aussi — on ne parle Android
 * qu'à qui le dit.
 *
 * Lu comme `X-Time-Zone`, mais sans rien écrire sur le compte : un même compte
 * raconte depuis un iPhone et depuis un Android, et c'est le tour qui sait
 * d'où il part. MEMO répond dans un job, hors de la requête : la plateforme
 * voyage donc **sur le tour** (`chat_messages.payload.platform`, posé par la
 * route seulement pour Android), sans migration.
 */
export type AppPlatform = "ios" | "android";

export function appPlatformOf(request: { headers: IncomingHttpHeaders }): AppPlatform {
  const header = request.headers["x-app-platform"];
  const raw = typeof header === "string" ? header.trim().toLowerCase() : "";
  return raw === "android" ? "android" : "ios";
}

/**
 * Ce qu'un tour du voyageur porte dans son `payload` pour sa plateforme :
 * rien pour un iPhone — les tours d'avant ce lot, et ceux des builds iOS,
 * restent tels qu'ils étaient.
 */
export function platformPayload(platform: AppPlatform): { platform?: "android" } {
  return platform === "android" ? { platform: "android" } : {};
}

/** La plateforme d'un tour, relue dans son `payload` par le job. */
export function platformOfPayload(payload: unknown): AppPlatform {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return "ios";
  return (payload as { platform?: unknown }).platform === "android" ? "android" : "ios";
}
