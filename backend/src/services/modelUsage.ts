import type { Logger } from "pino";

/**
 * Ce qu'un appel au modèle a consommé, tel que l'API le rend. Les champs sont
 * tous optionnels à dessein : un ancien modèle, un proxy, un refus très tôt
 * peuvent n'en renvoyer qu'une partie, et un compteur qui plante vaut moins
 * qu'un compteur incomplet.
 */
export interface RawModelUsage {
  input_tokens?: number | null;
  output_tokens?: number | null;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
}

/** Ce qu'on écrit dans les logs pour un appel. Exporté pour être testé. */
export interface ModelUsageLine {
  step: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  maxTokens: number;
  /** Ce qu'il restait sous le plafond, en pourcentage. */
  headroomPercent: number | null;
}

/**
 * Sous cette marge, le plafond est à portée du prochain souvenir : la
 * réflexion grandit avec le carnet, et ce qui passe aujourd'hui échouera.
 */
export const HEADROOM_WARNING_PERCENT = 20;

/** Le compte d'un appel, prêt à écrire. */
export function modelUsageLine(
  step: string,
  model: string,
  maxTokens: number,
  usage: RawModelUsage | null | undefined,
): ModelUsageLine {
  const outputTokens = usage?.output_tokens ?? 0;
  return {
    step,
    model,
    inputTokens: usage?.input_tokens ?? 0,
    outputTokens,
    cacheReadTokens: usage?.cache_read_input_tokens ?? 0,
    cacheWriteTokens: usage?.cache_creation_input_tokens ?? 0,
    maxTokens,
    // Sans plafond connu, pas de marge : mieux vaut rien dire que dire 100 %.
    headroomPercent:
      maxTokens > 0 ? Math.max(0, Math.round((1 - outputTokens / maxTokens) * 100)) : null,
  };
}

/**
 * **Écrit ce qu'un appel au modèle a coûté.** Une ligne par appel payé, au
 * pied de l'appel : le compte ne remonte pas par les types, donc personne ne
 * peut oublier de le passer.
 *
 * ⚠️ **Pourquoi ça existe.** Le compte Anthropic est prépayé et partagé avec
 * l'app. Fin octobre 2026 il s'est vidé, et **rien dans les logs ne l'a dit** :
 * les rédactions tombaient, MEMO répondait « c'est enregistré », et on l'a
 * découvert deux semaines plus tard en lisant `redactionError` en base. On ne
 * savait ni combien un souvenir coûte, ni où partait le crédit.
 *
 * Le second usage est moins évident, et c'est le plus utile : la réflexion
 * adaptative se facture **en sortie** et partage le plafond avec le texte. Un
 * appel qui sort 60 000 jetons sur un plafond de 64 000 n'a pas échoué — mais
 * il va échouer au souvenir suivant, parce que le prompt grandit avec le
 * carnet. `headroomPercent` est ce rapport, et il aurait annoncé la panne du
 * 17/11/2026 au lieu de la subir (`RECIT_MAX_TOKENS`, `docs/modeles-ia.md`
 * § 8).
 *
 * Les prix ne sont **pas** calculés ici : ils vivent dans
 * `docs/modeles-ia.md` § 2, et une constante de tarif oubliée dans le code
 * mentirait longtemps avant qu'on s'en aperçoive. Les jetons, eux, ne
 * périment pas.
 */
export function logModelUsage(
  logger: Logger,
  step: string,
  model: string,
  maxTokens: number,
  usage: RawModelUsage | null | undefined,
): ModelUsageLine {
  const line = modelUsageLine(step, model, maxTokens, usage);
  logger.info(line, "Jetons consommés");
  if (line.headroomPercent !== null && line.headroomPercent < HEADROOM_WARNING_PERCENT) {
    logger.warn(line, "Plafond de jetons bientôt atteint : la réflexion prend la place du texte");
  }
  return line;
}
