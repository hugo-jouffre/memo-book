import { tellPageCountChanged } from "../services/conversationThread.js";
import { changementDePages, pageCountChangeText } from "../services/pageCountChange.js";
import type { Prisma } from "@prisma/client";
import { groupSteps, pagesAvantEtapes } from "../services/payloadValidator.js";
import type { AppContext } from "../context.js";
import type { BookPayload } from "../services/structuring.js";

export interface RenderJob {
  renderId: string;
}

/**
 * Étape 3 : le payload part chez APITemplate.io, qui compose le PDF avec le
 * template HTML/CSS de `MemoBook Generator/templates/travel-journal/`. On stocke l'URL du PDF et
 * la référence de transaction, seule trace exploitable en cas de litige avec
 * le fournisseur.
 */
export async function renderBook(
  context: AppContext,
  { renderId }: RenderJob,
): Promise<void> {
  const { prisma, renderer, logger } = context;

  const render = await prisma.render.findUnique({ where: { id: renderId } });

  if (!render) {
    logger.warn({ renderId }, "Rendu introuvable, job d'impression ignoré");
    return;
  }

  if (!render.payload) {
    const message = "Le rendu n'a pas de payload : l'étape de structuration a échoué.";
    await prisma.render.update({
      where: { id: renderId },
      data: { status: "failed", error: message },
    });
    logger.error({ renderId }, message);
    return;
  }

  try {
    const result = await renderer.render(render.payload as BookPayload);
    const pageCount = composedPageCount(render.payload);
    // Les chapitres de **ce** PDF, pour n'en partager que quelques-uns (T285).
    const chapters = composedChapters(render.payload);

    await prisma.render.update({
      where: { id: renderId },
      data: {
        status: "ready",
        pdfUrl: result.pdfUrl,
        apitemplateTransactionId: result.transactionId,
        pageCount,
        chapters: chapters as unknown as Prisma.InputJsonArray,
        error: null,
      },
    });

    // **Le carnet existe, il s'imprime** (T228) : `isPrintable` n'était écrit
    // que par le jeu d'essai, si bien que l'imprimante des voyages passés de
    // l'accueil n'apparaissait jamais sur un vrai voyage. Et ses pages, que
    // l'accueil et le prix lisent (`billablePages`) — seulement si aucun rendu
    // plus récent n'a déjà parlé.
    const newer = await prisma.render.count({
      where: { memoId: render.memoId, status: "ready", createdAt: { gt: render.createdAt } },
    });
    const avant = await prisma.memo.findUnique({
      where: { id: render.memoId },
      select: { pageCount: true, targetPageCount: true },
    });
    await prisma.memo.update({
      where: { id: render.memoId },
      data: { isPrintable: true, ...(newer === 0 && pageCount !== null ? { pageCount } : {}) },
    });

    // **Quand le carnet change de prix, MEMO le dit** (T265, 24/11/2026).
    // Pas à chaque changement de pagination : l'aperçu se recompose sans
    // cesse, et l'accueil affiche déjà les pages. C'est le **prix**, par
    // palier, que personne ne voit venir — voir `services/pageCountChange.ts`.
    // Seulement sur le rendu le plus récent : un vieux rendu qui finit après
    // un neuf ne raconte pas le carnet d'aujourd'hui.
    if (newer === 0 && avant) {
      const change = changementDePages(avant.pageCount, pageCount, avant.targetPageCount);
      if (change) {
        await tellPageCountChanged(prisma, render.memoId, pageCountChangeText(change)).catch(
          (cause: unknown) => {
            logger.warn({ err: cause, renderId }, "Le changement de pages n'a pas pu se dire");
            return false;
          },
        );
      }
    }

    logger.info({ renderId, pdfUrl: result.pdfUrl, pageCount }, "Carnet généré");
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.render.update({
      where: { id: renderId },
      data: { status: "failed", error: message },
    });
    // Pas de nouvel essai automatique : voir `jobs/structure.ts`.
    logger.error({ err: cause, renderId }, "Composition du PDF échouée");
  }
}

/**
 * Les pages du carnet composé, **hors couvertures** — le même compte que la
 * cible (`recalerSurLaCible`) : le colophon, l'introduction et les pages
 * blanches d'avant (`pagesAvantEtapes`), une page par entrée de `days[]`, et
 * la page blanche finale qui rend l'intérieur pair. C'est le nombre qui fait
 * le prix (`billablePages`, Hugo, 18/10/2026) ; il ne comptait que les pages
 * d'étape. `null` pour un payload qui n'en a pas.
 */
/** Un chapitre du carnet composé, et les pages qu'il occupe dans le PDF. */
export interface ComposedChapter {
  /** Le titre de l'étape, tel que le carnet l'imprime. */
  title: string;
  /** Sa première page dans le PDF, **1 pour la première page du document**. */
  firstPage: number;
  /** Combien de pages elle occupe. */
  pageCount: number;
}

/**
 * **Les chapitres du carnet composé, et leurs pages** (T285, Hugo, 05/11/2026
 * — « au partage d'un PDF, pouvoir choisir ce qu'on envoie »).
 *
 * Rien à calculer qui ne se déduise : le carnet composé fait **une page par
 * entrée de `days[]`** (voir `composedPageCount` ci-dessous), `groupSteps` les
 * regroupe déjà par étape sur `day_intro`, et `pagesAvantEtapes` donne le
 * décalage de tête — le colophon, l'introduction, les pages blanches.
 *
 * ⚠️ **Hors couvertures**, comme tout ce qui compte les pages ici. Le PDF que
 * l'app télécharge les porte, lui : c'est à elle d'en tenir compte, et son
 * modèle le dit (`BookChapter`).
 *
 * `[]` pour un payload sans journée — il n'y a alors rien à choisir.
 */
export function composedChapters(payload: unknown): ComposedChapter[] {
  const record = payload as Record<string, unknown> | null;
  const days = record?.["days"];
  if (!Array.isArray(days)) return [];

  const avant = pagesAvantEtapes(record!);
  return groupSteps(days as Record<string, unknown>[]).map((etape) => {
    const premiere = etape.days[0] ?? {};
    const intro = (premiere["day_intro"] ?? {}) as Record<string, unknown>;
    const titre = [premiere["title"], intro["location"], premiere["city"]]
      .map((v) => (typeof v === "string" ? v.trim() : ""))
      .find((v) => v.length > 0);
    return {
      // Sans titre ni lieu, le numéro : une ligne vide ne se coche pas.
      title: titre ?? `Étape ${etape.start + 1}`,
      firstPage: avant + etape.start + 1,
      pageCount: etape.days.length,
    };
  });
}

export function composedPageCount(payload: unknown): number | null {
  const record = payload as Record<string, unknown> | null;
  const days = record?.["days"];
  if (!Array.isArray(days)) return null;
  return pagesAvantEtapes(record!) + days.length + (record!["page_blanche_finale"] ? 1 : 0);
}
