import { createHash } from "node:crypto";
import OpenAI from "openai";
import type { Env } from "../env.js";

export interface TranscriptionInput {
  audio: Buffer;
  filename: string;
  mimeType: string;
  /** Indice de langue. MemoBook est francophone par défaut. */
  language?: string;
  /** Les noms que le carnet connaît déjà (`transcriptionHintFor`). */
  hint?: string;
}

export interface TranscriptionResult {
  text: string;
  /** Durée détectée, quand le fournisseur la renvoie. */
  durationSeconds?: number;
}

export interface Transcriber {
  transcribe(input: TranscriptionInput): Promise<TranscriptionResult>;
}

/**
 * Transcription réelle via l'API OpenAI. La langue est forcée : sans elle, les
 * vocaux courts et les noms de lieux étrangers font régulièrement basculer la
 * détection automatique vers l'anglais.
 */
export class OpenAITranscriber implements Transcriber {
  constructor(
    private readonly client: OpenAI,
    private readonly model: string,
  ) {}

  async transcribe(input: TranscriptionInput): Promise<TranscriptionResult> {
    const file = new File([new Uint8Array(input.audio)], input.filename, {
      type: input.mimeType,
    });

    const response = await this.client.audio.transcriptions.create({
      file,
      model: this.model,
      language: input.language ?? "fr",
      ...(input.hint ? { prompt: input.hint } : {}),
    });

    return { text: response.text.trim() };
  }
}

/** Au-delà, l'indice cesse d'aider : le transcripteur ne lit que le début de son contexte. */
export const TRANSCRIPTION_HINT_MAX_CHARS = 400;

/**
 * L'indice passé au transcripteur : qui raconte, avec qui, où, et les noms
 * que le carnet a déjà fixés. Sans lui, la machine écrit « Famine » pour Fanny
 * et « Cora » pour Chora ; avec, elle épelle comme le carnet.
 *
 * **Des noms propres, rien d'autre** : personnes et lieux de la fiche de
 * cohérence, jamais son lexique. Un mot mal entendu qui s'y serait glissé,
 * soufflé au transcripteur, reviendrait à chaque vocal. Les lieux les plus
 * récents passent en premier — ce sont eux qu'on raconte ce soir.
 */
export function transcriptionHintFor(known: {
  narrator: string | null;
  companions: readonly string[];
  destination: string | null;
  people: readonly string[];
  places: readonly string[];
}): string | undefined {
  const travellers = [...new Set([known.narrator, ...known.companions, ...known.people])].filter(
    (name): name is string => Boolean(name),
  );
  const places = [...new Set([...known.places].reverse())].filter(Boolean);
  if (travellers.length === 0 && places.length === 0 && !known.destination) return undefined;

  let hint = "Récit de voyage";
  if (travellers.length > 0) {
    const last = travellers.pop()!;
    hint += ` de ${travellers.length > 0 ? `${travellers.join(", ")} et ${last}` : last}`;
  }
  if (known.destination) hint += ` (${known.destination})`;
  hint += ".";
  for (const [index, place] of places.entries()) {
    const next = `${hint}${index === 0 ? " Lieux : " : ", "}${place}`;
    if (next.length + 1 > TRANSCRIPTION_HINT_MAX_CHARS) break;
    hint = next;
  }
  if (places.length > 0 && !hint.endsWith(".")) hint += ".";
  return hint.slice(0, TRANSCRIPTION_HINT_MAX_CHARS);
}

/**
 * Transcription déterministe pour les tests et le smoke local : aucun appel
 * réseau, aucune clé. Le texte produit dépend du contenu de l'audio, ce qui
 * permet de vérifier que la bonne pièce jointe traverse bien le pipeline.
 */
export class FakeTranscriber implements Transcriber {
  /** Textes injectés d'avance, consommés dans l'ordre des appels. */
  constructor(private readonly scriptedTexts: string[] = []) {}

  private callCount = 0;

  /** Les indices reçus, dans l'ordre des appels : ce que le job a su souffler. */
  readonly hints: (string | undefined)[] = [];

  async transcribe(input: TranscriptionInput): Promise<TranscriptionResult> {
    const scripted = this.scriptedTexts[this.callCount];
    this.callCount += 1;
    this.hints.push(input.hint);

    if (scripted !== undefined) {
      return { text: scripted, durationSeconds: 12 };
    }

    const fingerprint = createHash("sha256")
      .update(input.audio)
      .digest("hex")
      .slice(0, 8);

    return {
      text: `Transcription simulée de ${input.filename} (${fingerprint}).`,
      durationSeconds: 12,
    };
  }
}

export function createTranscriber(env: Env): Transcriber {
  if (!env.live) return new FakeTranscriber();
  return new OpenAITranscriber(
    new OpenAI({ apiKey: env.OPENAI_API_KEY }),
    env.OPENAI_TRANSCRIPTION_MODEL,
  );
}
