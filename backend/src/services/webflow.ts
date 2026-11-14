import { createHash } from "node:crypto";
import type { Env } from "../env.js";

export interface PublishedAsset {
  assetId: string;
  cdnUrl: string;
}

/**
 * APITemplate.io télécharge les images au moment du rendu : il lui faut des URLs
 * publiques. Les photos passent donc par le CDN Webflow de memo-book.com, comme
 * décrit dans le README à la racine du dépôt.
 */
export interface AssetPublisher {
  /**
   * Vrai quand `publish` rend une adresse que le monde peut lire.
   *
   * Faux pour la publication simulée, et c'est tout l'intérêt : son adresse
   * `cdn.example.test` partait dans le payload du carnet, qui se composait
   * alors sans une seule photo, sans que rien ne le dise (Hugo, 11/11/2026).
   * `services/renderPhotos.ts` sert la photo par l'API quand c'est faux.
   */
  readonly servesPublicUrls: boolean;

  publish(filename: string, sourceUrl: string): Promise<PublishedAsset>;
  /**
   * Retire la copie publique d'une photo — son souvenir, son voyage ou son
   * compte est parti. Un fichier déjà absent compte comme retiré : la
   * suppression se rejoue sans risque (`jobs/eraseTrace.ts`).
   */
  unpublish(assetId: string): Promise<void>;
}

export class WebflowAssetPublisher implements AssetPublisher {
  readonly servesPublicUrls = true;

  constructor(
    private readonly token: string,
    private readonly siteId: string,
    private readonly endpoint = "https://api.webflow.com/assets/upload",
    private readonly assetsEndpoint = "https://api.webflow.com/v2/assets",
  ) {}

  async publish(filename: string, sourceUrl: string): Promise<PublishedAsset> {
    const response = await fetch(this.endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${this.token}`,
        accept: "application/json",
        "content-type": "application/json",
      },
      body: JSON.stringify({ siteId: this.siteId, fileName: filename, url: sourceUrl }),
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(
        `Upload Webflow échoué (HTTP ${response.status}) pour ${filename} : ${body.slice(0, 500)}`,
      );
    }

    const payload = (await response.json()) as {
      assetId?: string;
      id?: string;
      cdnUrl?: string;
      url?: string;
    };

    const assetId = payload.assetId ?? payload.id;
    const cdnUrl = payload.cdnUrl ?? payload.url;

    if (!assetId || !cdnUrl) {
      throw new Error(
        `Réponse Webflow inattendue pour ${filename} : ${JSON.stringify(payload).slice(0, 500)}`,
      );
    }

    return { assetId, cdnUrl };
  }

  async unpublish(assetId: string): Promise<void> {
    const response = await fetch(`${this.assetsEndpoint}/${encodeURIComponent(assetId)}`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${this.token}`, accept: "application/json" },
    });

    // 404 : déjà retiré, par un essai précédent ou à la main. C'est le but.
    if (response.ok || response.status === 404) return;

    const body = await response.text();
    throw new Error(
      `Suppression Webflow échouée (HTTP ${response.status}) pour ${assetId} : ${body.slice(0, 500)}`,
    );
  }
}

/**
 * L'hôte des adresses simulées. `.test` est réservé à ça par la RFC 2606 : il
 * ne résout nulle part, et c'est bien le but — une adresse simulée doit rater
 * franchement, jamais atterrir chez quelqu'un.
 */
export const SIMULATED_CDN_HOST = "cdn.example.test";

/**
 * **Cette adresse de CDN ne sert personne.**
 *
 * À vérifier avant de la donner à qui que ce soit, parce qu'une adresse
 * simulée **écrite en base** y reste : jusqu'au 11/11/2026, chaque photo qui
 * passait dans un carnet se voyait poser celle-ci, et 68 photos de production
 * la portaient encore le 14/11. Le moteur de PDF allait les chercher sur un
 * domaine qui ne résout pas et composait des cadres vides ; l'app affichait
 * des vignettes grises. Deux symptômes, une seule cause, et rien dans les
 * journaux — d'où ce garde-fou plutôt qu'un simple nettoyage de la base.
 */
export function isSimulatedCdnUrl(url: string | null | undefined): boolean {
  return typeof url === "string" && url.includes(`://${SIMULATED_CDN_HOST}/`);
}

/** Publication simulée : renvoie une URL stable et déterministe. */
export class FakeAssetPublisher implements AssetPublisher {
  readonly servesPublicUrls = false;

  async publish(filename: string, sourceUrl: string): Promise<PublishedAsset> {
    const assetId = createHash("sha256").update(sourceUrl).digest("hex").slice(0, 24);
    return {
      assetId,
      cdnUrl: `https://${SIMULATED_CDN_HOST}/memobook/${assetId}/${encodeURIComponent(filename)}`,
    };
  }

  /** Rien n'a été publié : rien à retirer. */
  async unpublish(): Promise<void> {}
}

export function createAssetPublisher(env: Env): AssetPublisher {
  if (!env.live || !env.WEBFLOW_API_TOKEN || !env.WEBFLOW_SITE_ID) {
    return new FakeAssetPublisher();
  }
  return new WebflowAssetPublisher(env.WEBFLOW_API_TOKEN, env.WEBFLOW_SITE_ID);
}
