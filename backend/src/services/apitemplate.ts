import { createHash } from "node:crypto";
import type { Env } from "../env.js";
import { assertNoNullValues, type RenderProfile } from "./bookPdf.js";
import { LocalChromiumRenderer } from "./localRenderer.js";
import type { BookPayload } from "./structuring.js";

export interface RenderedBook {
  transactionId: string;
  pdfUrl: string;
}

export interface BookRenderer {
  render(payload: BookPayload): Promise<RenderedBook>;
}

/**
 * Rendu du PDF par APITemplate.io, sur le template alimenté par
 * `templates/travel-journal/` (voir .github/workflows/sync-apitemplate.yml).
 * Le contrat est celui de `templates/travel-journal/apitemplate-openapi.yaml`.
 */
export class ApiTemplateRenderer implements BookRenderer {
  constructor(
    private readonly apiKey: string,
    private readonly templateId: string,
    private readonly baseUrl = "https://rest-de.apitemplate.io/v2",
    private readonly profile: RenderProfile = "preview",
  ) {}

  async render(payload: BookPayload): Promise<RenderedBook> {
    // Jinja2 imprime `None` là où l'on attend une chaîne vide : un null qui
    // passe ici écrirait le mot « None » dans le carnet imprimé.
    assertNoNullValues(payload);

    const url = new URL(`${this.baseUrl}/create-pdf`);
    url.searchParams.set("template_id", this.templateId);

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-API-KEY": this.apiKey,
      },
      // `render_profile` décide du fond (blanc imprimeur / crème aperçu).
      body: JSON.stringify({ render_profile: this.profile, ...payload }),
    });

    const body = (await response.json().catch(() => null)) as {
      status?: string;
      message?: string;
      transaction_ref?: string;
      download_url?: string;
    } | null;

    if (!response.ok || body?.status !== "success") {
      throw new Error(
        `APITemplate a refusé le rendu (HTTP ${response.status}) : ${
          body?.message ?? "réponse illisible"
        }`,
      );
    }

    if (!body.download_url) {
      throw new Error("APITemplate a répondu `success` sans `download_url`.");
    }

    return {
      transactionId: body.transaction_ref ?? "",
      pdfUrl: body.download_url,
    };
  }
}

/** Rendu simulé : ne produit pas de PDF, mais valide le reste de la chaîne. */
export class FakeBookRenderer implements BookRenderer {
  async render(payload: BookPayload): Promise<RenderedBook> {
    const transactionId = createHash("sha256")
      .update(JSON.stringify(payload))
      .digest("hex")
      .slice(0, 24);

    return {
      transactionId,
      pdfUrl: `https://pdf.example.test/memobook/${transactionId}.pdf`,
    };
  }
}

function apiTemplateRenderer(env: Env): ApiTemplateRenderer {
  return new ApiTemplateRenderer(
    env.APITEMPLATE_API_KEY,
    env.APITEMPLATE_TEMPLATE_ID,
    env.APITEMPLATE_BASE_URL,
    env.RENDER_PROFILE,
  );
}

export function createBookRenderer(env: Env): BookRenderer {
  switch (env.RENDERER) {
    case "fake":
      return new FakeBookRenderer();
    case "apitemplate":
      return apiTemplateRenderer(env);
    case "local":
      return new LocalChromiumRenderer(
        env.RENDER_OUTPUT_DIR,
        env.RENDER_PUBLIC_BASE_URL || `http://localhost:${env.PORT}/v1/local-renders`,
        env.RENDER_PROFILE,
      );
    default:
      // `auto` : le comportement historique, piloté par PIPELINE_MODE.
      return env.live ? apiTemplateRenderer(env) : new FakeBookRenderer();
  }
}
