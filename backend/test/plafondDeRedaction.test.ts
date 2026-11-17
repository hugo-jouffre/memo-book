import type Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import {
  AnthropicRedactor,
  EMPTY_COHERENCE_SHEET,
  type RedactionInput,
} from "../src/services/redaction.js";

/**
 * Le plafond de jetons de la rédaction, et ce qu'on dit quand il est atteint.
 *
 * Le 17/11/2026, sur le carnet de Hugo, la rédaction tombait à 1 944
 * caractères de transcription pendant qu'un souvenir de 4 273 passait : la
 * réflexion adaptative se compte dans `max_tokens`, et à 16 000 elle absorbait
 * le budget avant que le JSON soit écrit. Le message d'erreur, lui, envoyait le
 * voyageur raccourcir un récit qui n'y était pour rien.
 *
 * Rien n'exerçait cette branche : `AnthropicRedactor` veut un client, et les
 * tests passaient tous par `FakeRedactor`. On lui en pose un faux.
 */

/**
 * Ce que le SDK rend : un flux dont `finalMessage()` donne le message entier.
 *
 * `redact` fait **deux** appels — le récit puis le relevé —, et chacun a son
 * plafond. On les garde tous les deux : ne retenir que le dernier ferait passer
 * le plafond du relevé pour celui du récit.
 */
function clientQuiRend(message: unknown, appels: Record<string, unknown>[]): Anthropic {
  // Un seul transtypage, ici : `AnthropicRedactor` ne touche que `messages`,
  // et le reste du client n'a pas à être imité pour ces trois cas.
  return {
    messages: {
      stream(requete: Record<string, unknown>) {
        appels.push(requete);
        return { finalMessage: async () => message };
      },
      create() {
        throw new Error("La rédaction doit être diffusée, pas demandée d'un coup.");
      },
    },
  } as unknown as Anthropic;
}

function souvenir(): RedactionInput {
  return {
    memo: { title: "Japon", subtitle: null, authors: null, theme: null, styleKey: null },
    entry: { transcript: "Le marché de Nishiki au petit matin.", capturedAt: new Date(), placeLabel: null },
    coherenceSheet: EMPTY_COHERENCE_SHEET,
    previous: [],
  };
}

describe("le plafond de jetons de la rédaction", () => {
  it("laisse au récit la place d'aller jusqu'au texte, et borne le relevé", async () => {
    const appels: Record<string, unknown>[] = [];
    const client = clientQuiRend(
      { stop_reason: "end_turn", content: [{ type: "text", text: JSON.stringify({ text: "ok" }) }] },
      appels,
    );
    const redactor = new AnthropicRedactor(client, "claude-opus-5");

    await redactor.redact(souvenir()).catch(() => undefined);

    // Le récit demande large : la réflexion partage ce plafond avec lui.
    expect(appels[0]?.max_tokens).toBe(64_000);
    // Le relevé ne fait que lister, à effort bas : il reste borné court.
    expect(appels[1]?.max_tokens).toBe(8_000);
  });

  it("diffuse les deux demandes, au lieu de les attendre d'un coup", async () => {
    // Un plafond large sans diffusion expire sur le délai HTTP du SDK : le
    // faux client lève si quelqu'un repasse par `create`.
    const appels: Record<string, unknown>[] = [];
    const client = clientQuiRend(
      { stop_reason: "end_turn", content: [{ type: "text", text: JSON.stringify({ text: "ok" }) }] },
      appels,
    );
    const redactor = new AnthropicRedactor(client, "claude-opus-5");

    await redactor.redact(souvenir()).catch(() => undefined);

    expect(appels).toHaveLength(2);
  });

  it("n'accuse pas la longueur du souvenir quand le plafond est atteint", async () => {
    const client = clientQuiRend({ stop_reason: "max_tokens", content: [] }, []);
    const redactor = new AnthropicRedactor(client, "claude-opus-5");

    const erreur = await redactor.redact(souvenir()).then(
      () => null,
      (cause: Error) => cause,
    );

    expect(erreur).toBeInstanceOf(Error);
    // ⚠️ Ce message part chez l'utilisateur (`routes/serializers.ts`). Il a
    // longtemps dit « le souvenir est probablement trop long pour une seule
    // étape » — faux, et c'est le voyageur qu'on envoyait corriger.
    expect(erreur?.message).not.toMatch(/trop long/);
    expect(erreur?.message).toMatch(/plafond/);
    // Et il dit où est le récit : nulle part ailleurs il n'apprend qu'il est sauf.
    expect(erreur?.message).toMatch(/intact/);
  });
});
