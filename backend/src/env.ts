import { z } from "zod";

/**
 * Toute la configuration passe par ici. Le serveur refuse de démarrer si une
 * variable requise manque, plutôt que d'échouer plus tard au milieu d'un job.
 */
const schema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  LOG_LEVEL: z
    .enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"])
    .default("info"),

  DATABASE_URL: z.string().min(1),

  // Optionnels ici, vérifiés au moment de construire le client dans
  // `createMediaStorage`. En test et pendant le smoke, le stockage est en
  // mémoire : exiger un bucket pour lancer les tests serait une friction
  // gratuite, et un défaut silencieux masquerait une erreur de configuration
  // en production.
  S3_ENDPOINT: z.string().url().optional(),
  S3_REGION: z.string().default("us-east-1"),
  S3_BUCKET: z.string().min(1).optional(),
  S3_ACCESS_KEY_ID: z.string().min(1).optional(),
  S3_SECRET_ACCESS_KEY: z.string().min(1).optional(),
  S3_FORCE_PATH_STYLE: z
    .enum(["true", "false"])
    .default("true")
    .transform((value) => value === "true"),

  OPENAI_API_KEY: z.string().default(""),
  OPENAI_TRANSCRIPTION_MODEL: z.string().default("gpt-4o-transcribe"),
  OPENAI_STRUCTURING_MODEL: z.string().default("gpt-4o"),

  /**
   * Rédaction du texte de carnet. Séparée d'OpenAI, qui reste sur la
   * transcription audio et la mise en page : la rédaction est l'étape où la
   * qualité se voit, et elle doit pouvoir changer de modèle sans toucher au
   * reste du pipeline.
   *
   * Sans clé, la rédaction bascule sur `FakeRedactor` même en mode `live` —
   * le carnet reste générable, avec un texte simplement nettoyé.
   */
  ANTHROPIC_API_KEY: z.string().default(""),
  ANTHROPIC_REDACTION_MODEL: z.string().default("claude-opus-5"),

  PIPELINE_MODE: z.enum(["auto", "live", "fake"]).default("auto"),

  APITEMPLATE_API_KEY: z.string().default(""),
  APITEMPLATE_TEMPLATE_ID: z.string().default("7a177b23210099d6"),
  // Le compte MemoBook est hébergé en région DE. Pointer sur rest.apitemplate.io
  // renvoie une erreur d'authentification trompeuse.
  APITEMPLATE_BASE_URL: z.string().url().default("https://rest-de.apitemplate.io/v2"),

  /**
   * Axe distinct de `PIPELINE_MODE`, volontairement.
   *
   * `PIPELINE_MODE` pilote `live`, qui choisit aussi le transcripteur, le
   * structureur et Webflow. Or la boucle de travail sur la mise en page, c'est
   * « transcription simulée + vrai PDF » : seul un axe séparé l'exprime.
   * `auto` conserve exactement le comportement historique.
   */
  RENDERER: z.enum(["auto", "apitemplate", "local", "fake"]).default("auto"),
  RENDER_OUTPUT_DIR: z.string().default(".render-out"),
  RENDER_PUBLIC_BASE_URL: z.string().default(""),
  RENDER_PROFILE: z.enum(["print", "preview"]).default("preview"),

  WEBFLOW_API_TOKEN: z.string().default(""),
  WEBFLOW_SITE_ID: z.string().default(""),
});

export type Env = z.infer<typeof schema> & {
  /** `true` quand le pipeline doit appeler les APIs externes pour de vrai. */
  live: boolean;
};

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);

  if (!parsed.success) {
    const details = parsed.error.issues
      .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
      .join("\n");
    throw new Error(
      `Configuration invalide. Vérifie ton .env (voir .env.example) :\n${details}`,
    );
  }

  const env = parsed.data;
  const hasLiveKeys = env.OPENAI_API_KEY !== "" && env.APITEMPLATE_API_KEY !== "";

  let live: boolean;
  switch (env.PIPELINE_MODE) {
    case "live":
      if (!hasLiveKeys) {
        throw new Error(
          "PIPELINE_MODE=live mais OPENAI_API_KEY et/ou APITEMPLATE_API_KEY sont vides.",
        );
      }
      live = true;
      break;
    case "fake":
      live = false;
      break;
    default:
      live = hasLiveKeys;
  }

  if (env.RENDERER === "apitemplate" && env.APITEMPLATE_API_KEY === "") {
    throw new Error("RENDERER=apitemplate mais APITEMPLATE_API_KEY est vide.");
  }

  return { ...env, live };
}
