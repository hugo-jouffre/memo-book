import { randomInt } from "node:crypto";

/**
 * Le code d'accès d'un voyage : six caractères qu'on partage pour y convier
 * quelqu'un.
 *
 * **L'alphabet est amputé de tout ce qui se confond** — ni O ni 0, ni I ni 1 —
 * parce qu'un code se recopie à la main, parfois d'après une capture d'écran ou
 * une dictée. Il reste trente-deux caractères, soit un milliard de codes : de
 * quoi ne jamais avoir à se soucier des collisions, et bien assez court pour
 * tenir dans un message.
 */
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const LENGTH = 6;

/**
 * Un code tiré au sort. `randomInt` et non `Math.random` : le code **est** le
 * droit d'entrer dans un carnet, personne ne doit pouvoir deviner la suite.
 */
export function makeAccessCode(): string {
  let code = "";
  for (let i = 0; i < LENGTH; i += 1) code += ALPHABET[randomInt(ALPHABET.length)];
  return code;
}
