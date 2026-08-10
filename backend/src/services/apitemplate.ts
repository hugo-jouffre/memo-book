import { createHash } from "node:crypto";
import type { Env } from "../env.js";
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
    private readonly baseUrl = "https://rest.apitemplate.io/v2",
  ) {}

  async render(payload: BookPayload): Promise<RenderedBook> {
    const url = new URL(`${this.baseUrl}/create-pdf`);
    url.searchParams.set("template_id", this.templateId);

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-API-KEY": this.apiKey,
      },
      body: JSON.stringify(payload),
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

export function createBookRenderer(env: Env): BookRenderer {
  if (!env.live) return new FakeBookRenderer();
  return new ApiTemplateRenderer(env.APITEMPLATE_API_KEY, env.APITEMPLATE_TEMPLATE_ID);
}
