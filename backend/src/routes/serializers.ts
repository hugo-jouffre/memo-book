import type { Entry, MediaAsset, Memo, Render } from "@prisma/client";

/**
 * Frontière explicite entre le modèle de base et ce que l'app reçoit.
 * Rien ne sort d'ici par accident : ni `tokenHash`, ni `storageKey`, ni le
 * payload complet du rendu.
 */

export function serializeMemo(memo: Memo) {
  return {
    id: memo.id,
    title: memo.title,
    subtitle: memo.subtitle,
    authors: memo.authors,
    theme: memo.theme,
    startDate: memo.startDate?.toISOString() ?? null,
    endDate: memo.endDate?.toISOString() ?? null,
    coverPhotoUrl: memo.coverPhotoUrl,
    createdAt: memo.createdAt.toISOString(),
    updatedAt: memo.updatedAt.toISOString(),
  };
}

export function serializeEntry(entry: Entry & { media?: MediaAsset | null }) {
  return {
    id: entry.id,
    memoId: entry.memoId,
    kind: entry.kind,
    status: entry.status,
    transcript: entry.transcript,
    capturedAt: entry.capturedAt.toISOString(),
    placeLabel: entry.placeLabel,
    error: entry.error,
    media: entry.media
      ? {
          id: entry.media.id,
          mimeType: entry.media.mimeType,
          bytes: entry.media.bytes,
          durationSeconds: entry.media.durationSeconds,
          cdnUrl: entry.media.cdnUrl,
        }
      : null,
    createdAt: entry.createdAt.toISOString(),
  };
}

export function serializeRender(render: Render) {
  return {
    id: render.id,
    memoId: render.memoId,
    status: render.status,
    pdfUrl: render.pdfUrl,
    error: render.error,
    createdAt: render.createdAt.toISOString(),
    updatedAt: render.updatedAt.toISOString(),
  };
}
