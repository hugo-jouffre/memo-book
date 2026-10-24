import { createHash } from "node:crypto";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import type { RenderProfile } from "./bookPdf.js";
import type { BookRenderer, RenderedBook } from "./apitemplate.js";
import type { CityStreetSource } from "./osmCity.js";
import type { BookPayload } from "./structuring.js";

/**
 * Rendu du carnet par le Chromium local, sans passer par APITemplate.
 *
 * Sert la boucle de travail sur la mise en page : le pipeline complet produit
 * un vrai PDF, immédiatement, sans clé d'API ni quota. Le fichier est servi par
 * la route `/v1/local-renders/:file`, parce que l'app iOS télécharge `pdfUrl`
 * en HTTP — un chemin `file://` ne lui servirait à rien.
 */
export class LocalChromiumRenderer implements BookRenderer {
  constructor(
    private readonly outputDir: string,
    private readonly publicBaseUrl: string,
    private readonly profile: RenderProfile,
    private readonly streets: CityStreetSource | null = null,
  ) {}

  async render(payload: BookPayload): Promise<RenderedBook> {
    // Import dynamique : `playwright-core` est une devDependency, le serveur de
    // production ne doit pas tenter de la charger au démarrage.
    const { renderBookPdf } = await import("./bookPdf.js");

    const transactionId = `local-${createHash("sha256")
      .update(JSON.stringify(payload))
      .digest("hex")
      .slice(0, 24)}`;

    const { pdf } = await renderBookPdf({
      payload,
      profile: this.profile,
      rues: await this.streets?.forPayload(payload),
    });

    const dir = resolve(this.outputDir);
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, `${transactionId}.pdf`), pdf);

    return { transactionId, pdfUrl: `${this.publicBaseUrl}/${transactionId}.pdf` };
  }

  /**
   * Efface le PDF posé sur le disque. Un rendu qui n'est pas d'ici (un PDF
   * d'APITemplate, quand le serveur local tourne sur la base de production)
   * est refusé plutôt qu'ignoré : la tâche échoue, et le journal le dit.
   */
  async discard(transactionId: string): Promise<void> {
    const filename = `${transactionId}.pdf`;
    if (!LOCAL_RENDER_FILENAME.test(filename)) {
      throw new Error(`Le rendu ${transactionId} n'a pas été composé ici : rien à effacer sur ce disque.`);
    }
    await rm(join(resolve(this.outputDir), filename), { force: true });
  }
}

/** Nom de fichier accepté par la route de service. Verrouillé contre la traversée. */
export const LOCAL_RENDER_FILENAME = /^local-[0-9a-f]{24}\.pdf$/;
