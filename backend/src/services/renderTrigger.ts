import type { Render } from "@prisma/client";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type StructureJob } from "../jobs/index.js";
import { currentBookFingerprint } from "./bookFingerprint.js";

export interface RenderTrigger {
  render: Render;
  /**
   * `true` quand une composition vient d'être lancée ; `false` quand on rend
   * celle qui tourne déjà, ou le dernier rendu prêt parce qu'il est à jour.
   */
  created: boolean;
}

/**
 * Au-delà, une composition « en cours » ne l'est plus : le worker est tombé,
 * ou le job s'est perdu. Elle est marquée en échec et une autre repart. Une
 * composition normale prend une à deux minutes, et peut attendre jusqu'à trois
 * minutes les souvenirs encore en rédaction (`jobs/structure.ts`) : vingt
 * minutes laissent une large marge sans laisser l'aperçu tourner pour rien
 * toute une soirée.
 */
export const STALE_RENDER_MS = 20 * 60 * 1000;

/**
 * Lance une composition du carnet, **seulement si elle sert à quelque chose**.
 *
 * Appelée à chaque ouverture de l'aperçu PDF (T224, Hugo 06/10/2026) — et par
 * la validation d'une étape, en fond. Trois réponses, dans cet ordre :
 *
 * 1. **Une composition tourne déjà** : on la rend. Deux appuis rapprochés ne
 *    produisent jamais deux PDF facturés.
 * 2. **Le dernier rendu prêt est à jour** — rien n'a changé depuis
 *    (`services/bookFingerprint.ts`) : on le rend, sans rien relancer.
 * 3. Sinon — jamais composé, échec, contenu modifié — une composition part.
 *
 * Les trois se décident **sous verrou** (la ligne du carnet, comme le fil de la
 * conversation) : deux ouvertures simultanées ne voient pas toutes deux « rien
 * en cours » et ne lancent pas deux compositions.
 *
 * Un `Render` est toujours **créé**, jamais réutilisé pour une composition
 * nouvelle : `PrintOrder.renderId` verrouille une commande sur une génération
 * précise (`onDelete: Restrict`), qui ne doit donc jamais changer après coup.
 */
export async function ensureRenderInProgress(
  context: AppContext,
  memoId: string,
  now: Date = new Date(),
): Promise<RenderTrigger> {
  const decision = await context.prisma.$transaction(async (tx) => {
    await tx.$executeRaw`SELECT id FROM memos WHERE id = ${memoId} FOR UPDATE`;

    const inFlight = await tx.render.findFirst({
      where: { memoId, status: { in: ["pending", "processing"] } },
      orderBy: { createdAt: "desc" },
    });
    if (inFlight && inFlight.updatedAt.getTime() > now.getTime() - STALE_RENDER_MS) {
      return { render: inFlight, created: false };
    }
    if (inFlight) {
      // Personne ne la finira : elle libère la place, et le dit.
      await tx.render.updateMany({
        where: { memoId, status: { in: ["pending", "processing"] }, updatedAt: { lte: inFlight.updatedAt } },
        data: { status: "failed", error: "La composition s’est interrompue." },
      });
    }

    const fingerprint = await currentBookFingerprint(tx, memoId);
    const lastReady = await tx.render.findFirst({
      where: { memoId, status: "ready", pdfUrl: { not: null } },
      orderBy: { createdAt: "desc" },
    });
    if (lastReady && fingerprint !== null && lastReady.inputFingerprint === fingerprint) {
      return { render: lastReady, created: false };
    }

    const render = await tx.render.create({ data: { memoId, inputFingerprint: fingerprint } });
    return { render, created: true };
  });

  if (!decision.created) return decision;

  // Publiée **après** la transaction : le job doit trouver le rendu en base.
  // Une file qui refuse (encore en train de démarrer) ne laisse pas derrière
  // elle un rendu « en cours » que personne ne traitera : il passe en échec,
  // et la prochaine ouverture de l'aperçu relance.
  try {
    await context.queue.publish<StructureJob>(JOB_NAMES.structure, {
      renderId: decision.render.id,
    });
  } catch (cause) {
    await context.prisma.render.updateMany({
      where: { id: decision.render.id, status: "pending" },
      data: { status: "failed", error: "La composition n’a pas pu démarrer." },
    });
    throw cause;
  }

  // La file en ligne des tests a déjà tout fait : on relit l'état réel.
  const current = await context.prisma.render.findUniqueOrThrow({
    where: { id: decision.render.id },
  });

  return { render: current, created: true };
}
