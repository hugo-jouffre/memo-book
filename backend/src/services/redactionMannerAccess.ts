/**
 * Qui peut changer la manière d'être rédigé — T292.
 *
 * Le réglage est réservé aux **abonnés illimités**, et la raison est le coût :
 * en changer reprend tout le carnet (`jobs/rewriteTrip.ts`), soit un appel au
 * modèle par étape déjà écrite.
 *
 * ⚠️ **Sauf carnet d'une seule étape**, où la reprise ne coûte qu'un appel —
 * c'est le carnet de quelqu'un qui commence, et lui refuser le réglage au nom
 * d'un coût d'un appel serait un paywall posé sur rien.
 *
 * La décision est une **fonction pure** : elle se teste sans base, et l'app
 * comme le serveur la lisent de la même façon — l'app pour pâlir le réglage
 * (jamais le désactiver, voir `ios/CLAUDE.md`), le serveur pour refuser.
 */

/** Pourquoi le réglage est ouvert, ou ne l'est pas. */
export type MannerAccess =
  /** Abonné illimité : ouvert, et la reprise peut être longue. */
  | { allowed: true; reason: "unlimited" }
  /** Carnet d'une seule étape : ouvert, la reprise ne coûte qu'un appel. */
  | { allowed: true; reason: "single_step" }
  /** Ni l'un ni l'autre : le réglage se montre, pâli, et mène au paywall. */
  | { allowed: false; reason: "needs_unlimited" };

export function mannerAccess(input: {
  isUnlimited: boolean;
  /** Le nombre d'étapes du carnet — `memo_steps`, pas le nombre de souvenirs. */
  stepCount: number;
}): MannerAccess {
  if (input.isUnlimited) return { allowed: true, reason: "unlimited" };
  // Zéro étape compte comme une : un carnet qui n'a encore rien à reprendre
  // est le cas le moins coûteux de tous, et le refuser serait absurde.
  if (input.stepCount <= 1) return { allowed: true, reason: "single_step" };
  return { allowed: false, reason: "needs_unlimited" };
}
