import { describe, expect, it } from "vitest";
import { HEADROOM_WARNING_PERCENT, logModelUsage, modelUsageLine } from "./modelUsage.js";
import type { Logger } from "pino";

/**
 * Le compteur de jetons — pourquoi il existe : le compte Anthropic est
 * prépayé, il s'est vidé fin octobre 2026, et **aucune ligne de log ne l'a
 * dit**. On l'a lu en base deux semaines plus tard.
 *
 * Et ce qu'il annonce : la réflexion adaptative se facture en sortie et
 * partage le plafond avec le texte. Un appel qui frôle son plafond n'a pas
 * échoué, mais le souvenir suivant échouera — le prompt grandit avec le
 * carnet.
 */

/** Un logger qui garde ce qu'on lui donne, pour relire ce qui a été écrit. */
function logueurQuiGarde() {
  const infos: Record<string, unknown>[] = [];
  const alertes: Record<string, unknown>[] = [];
  const logger = {
    info: (objet: Record<string, unknown>) => void infos.push(objet),
    warn: (objet: Record<string, unknown>) => void alertes.push(objet),
  } as unknown as Logger;
  return { logger, infos, alertes };
}

describe("le compteur de jetons", () => {
  it("écrit ce qu'un appel a consommé, cache compris", () => {
    const { logger, infos } = logueurQuiGarde();

    logModelUsage(logger, "recit", "claude-opus-5", 64_000, {
      input_tokens: 2_400,
      output_tokens: 6_000,
      cache_read_input_tokens: 25_900,
      cache_creation_input_tokens: 0,
    });

    expect(infos).toHaveLength(1);
    expect(infos[0]).toMatchObject({
      step: "recit",
      model: "claude-opus-5",
      inputTokens: 2_400,
      outputTokens: 6_000,
      // Les règles d'écriture relues depuis le cache : 10 % du tarif d'entrée,
      // et c'est l'essentiel du prompt. Les additionner au plein tarif
      // tripleraient le coût estimé.
      cacheReadTokens: 25_900,
      maxTokens: 64_000,
    });
  });

  it("alerte quand la réflexion prend la place du texte", () => {
    const { logger, infos, alertes } = logueurQuiGarde();

    // 58 000 sur 64 000 : l'appel a réussi. Le suivant, sur un carnet d'un
    // souvenir de plus, ne réussira pas — c'est tout l'intérêt de l'alerte.
    logModelUsage(logger, "recit", "claude-opus-5", 64_000, { output_tokens: 58_000 });

    expect(infos).toHaveLength(1);
    expect(alertes).toHaveLength(1);
    expect(alertes[0]).toMatchObject({ headroomPercent: 9 });
  });

  it("se tait quand il reste de la marge", () => {
    const { logger, alertes } = logueurQuiGarde();

    logModelUsage(logger, "recit", "claude-opus-5", 64_000, { output_tokens: 6_000 });

    expect(alertes).toHaveLength(0);
    expect(modelUsageLine("recit", "m", 64_000, { output_tokens: 6_000 }).headroomPercent).toBe(91);
  });

  it("ne dit pas une marge qu'il ne connaît pas, et ne compte pas NaN", () => {
    // Un refus très tôt, un proxy, un modèle plus ancien : l'usage peut
    // manquer. Un compteur qui plante vaut moins qu'un compteur à zéro, et
    // « 100 % de marge » serait un mensonge rassurant.
    expect(modelUsageLine("recit", "m", 0, undefined)).toMatchObject({
      inputTokens: 0,
      outputTokens: 0,
      headroomPercent: null,
    });
    expect(modelUsageLine("recit", "m", 64_000, {}).headroomPercent).toBe(100);
  });

  it("ne descend pas sous zéro quand la sortie dépasse le plafond annoncé", () => {
    expect(modelUsageLine("recit", "m", 1_000, { output_tokens: 4_000 }).headroomPercent).toBe(0);
    expect(HEADROOM_WARNING_PERCENT).toBe(20);
  });
});
