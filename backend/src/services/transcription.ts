import { createHash } from "node:crypto";
import OpenAI from "openai";
import type { Env } from "../env.js";

export interface TranscriptionInput {
  audio: Buffer;
  filename: string;
  mimeType: string;
  /** Indice de langue. MemoBook est francophone par défaut. */
  language?: string;
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
    });

    return { text: response.text.trim() };
  }
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

  async transcribe(input: TranscriptionInput): Promise<TranscriptionResult> {
    const scripted = this.scriptedTexts[this.callCount];
    this.callCount += 1;

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
