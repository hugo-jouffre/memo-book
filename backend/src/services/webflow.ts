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
  publish(filename: string, sourceUrl: string): Promise<PublishedAsset>;
}

export class WebflowAssetPublisher implements AssetPublisher {
  constructor(
    private readonly token: string,
    private readonly siteId: string,
    private readonly endpoint = "https://api.webflow.com/assets/upload",
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
}

/** Publication simulée : renvoie une URL stable et déterministe. */
export class FakeAssetPublisher implements AssetPublisher {
  async publish(filename: string, sourceUrl: string): Promise<PublishedAsset> {
    const assetId = createHash("sha256").update(sourceUrl).digest("hex").slice(0, 24);
    return {
      assetId,
      cdnUrl: `https://cdn.example.test/memobook/${assetId}/${encodeURIComponent(filename)}`,
    };
  }
}

export function createAssetPublisher(env: Env): AssetPublisher {
  if (!env.live || !env.WEBFLOW_API_TOKEN || !env.WEBFLOW_SITE_ID) {
    return new FakeAssetPublisher();
  }
  return new WebflowAssetPublisher(env.WEBFLOW_API_TOKEN, env.WEBFLOW_SITE_ID);
}
