import { createHash } from "node:crypto";
import type { Env } from "../env.js";
import { preparePayload, type RenderProfile } from "./bookPdf.js";
import { LocalChromiumRenderer } from "./localRenderer.js";
import { createCityStreetSource, type CityStreetSource } from "./osmCity.js";
import type { BookPayload } from "./structuring.js";

export interface RenderedBook {
  transactionId: string;
  pdfUrl: string;
}

export interface BookRenderer {
  render(payload: BookPayload): Promise<RenderedBook>;
  /**
   * Efface le PDF d'un rendu chez celui qui l'héberge — son voyage ou son
   * compte est parti. Se rejoue sans risque (`jobs/eraseTrace.ts`).
   */
  discard(transactionId: string): Promise<void>;
}

/** Où le rendu simulé fait semblant de poser ses PDF. Rien n'y est hébergé. */
export const FAKE_PDF_BASE_URL = "https://pdf.example.test/memobook/";

/**
 * Rendu du PDF par APITemplate.io, sur le template alimenté par
 * `MemoBook Generator/templates/travel-journal/` (voir .github/workflows/sync-apitemplate.yml).
 * Le contrat est celui de `MemoBook Generator/templates/travel-journal/gpt_image_schema.yaml`.
 */
export class ApiTemplateRenderer implements BookRenderer {
  constructor(
    private readonly apiKey: string,
    private readonly templateId: string,
    private readonly baseUrl = "https://rest-de.apitemplate.io/v2",
    private readonly profile: RenderProfile = "preview",
    private readonly streets: CityStreetSource | null = null,
  ) {}

  async render(payload: BookPayload): Promise<RenderedBook> {
    // Exactement la même préparation que le rendu local : validation des nulls
    // et dépliage des cartes de chapitre. Ce que l'aperçu montre est ce que
    // l'imprimeur recevra. Les rues des cartes de ville se demandent avant :
    // APITemplate ne reçoit que des SVG finis.
    const rues = await this.streets?.forPayload(payload);
    const prepared = preparePayload(payload, rues);

    const url = new URL(`${this.baseUrl}/create-pdf`);
    url.searchParams.set("template_id", this.templateId);

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-API-KEY": this.apiKey,
      },
      // `render_profile` décide du fond (blanc imprimeur / crème aperçu).
      body: JSON.stringify({ render_profile: this.profile, ...prepared }),
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

  /**
   * `GET /v2/delete-object` : retire le PDF du CDN d'APITemplate et marque la
   * transaction comme supprimée (https://apitemplate.io/apiv2/, lu le
   * 23/10/2026). Sans cet appel, le PDF reste en ligne à son URL — un carnet
   * entier, photos et récit, lisible par qui la connaît.
   */
  async discard(transactionId: string): Promise<void> {
    const url = new URL(`${this.baseUrl}/delete-object`);
    url.searchParams.set("transaction_ref", transactionId);

    const response = await fetch(url, { headers: { "X-API-KEY": this.apiKey } });
    const body = (await response.json().catch(() => null)) as {
      status?: string;
      message?: string;
    } | null;

    if (!response.ok || body?.status !== "success") {
      throw new Error(
        `APITemplate a refusé la suppression de ${transactionId} (HTTP ${response.status}) : ${
          body?.message ?? "réponse illisible"
        }`,
      );
    }
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
      pdfUrl: `${FAKE_PDF_BASE_URL}${transactionId}.pdf`,
    };
  }

  /** Aucun PDF n'existe : rien à effacer. */
  async discard(): Promise<void> {}
}

function apiTemplateRenderer(env: Env): ApiTemplateRenderer {
  return new ApiTemplateRenderer(
    env.APITEMPLATE_API_KEY,
    env.APITEMPLATE_TEMPLATE_ID,
    env.APITEMPLATE_BASE_URL,
    env.RENDER_PROFILE,
    createCityStreetSource(env),
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
        createCityStreetSource(env),
      );
    default:
      // `auto` : APITemplate quand le pipeline est réel et que sa clé est là,
      // sinon un rendu simulé — le reste du pipeline n'en dépend pas.
      return env.live && env.APITEMPLATE_API_KEY !== ""
        ? apiTemplateRenderer(env)
        : new FakeBookRenderer();
  }
}
