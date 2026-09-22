import type {
  Entry,
  MediaAsset,
  Memo,
  PrintOrder,
  PrintOrderCopy,
  Render,
} from "@prisma/client";
import type { PrintQuote } from "../services/printPricing.js";

/** Une commande et, quand elles ont été chargées, les options de ses exemplaires. */
type PrintOrderWithCopies = PrintOrder & { copyOptions?: PrintOrderCopy[] };

/** Les montants voyagent en euros, arrondis au centime. La base ne connaît que des centimes entiers. */
function euros(cents: number): number {
  return Number((cents / 100).toFixed(2));
}

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
    redactedText: entry.redactedText,
    redactionStatus: entry.redactionStatus,
    redactionError: entry.redactionError,
    editedText: entry.editedText,
    editedAt: entry.editedAt?.toISOString() ?? null,
    /** « Ça me convient » — voir `services/quota.ts`. */
    validatedAt: entry.validatedAt?.toISOString() ?? null,
    /**
     * Le texte que l'app affiche, calculé côté serveur pour que la règle de
     * priorité ne soit pas réimplémentée — et donc divergente — dans chaque
     * client.
     */
    displayText: entry.editedText ?? entry.redactedText ?? entry.transcript,
    suggestedTitle: entry.suggestedTitle,
    funFact: entry.funFact,
    funFactTitle: entry.funFactTitle,
    weatherKey: entry.weatherKey,
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

export function serializePrintOrder(order: PrintOrderWithCopies) {
  return {
    id: order.id,
    memoId: order.memoId,
    renderId: order.renderId,
    orderedByAccountId: order.orderedByAccountId,
    status: order.status,
    copies: order.copies,
    shippingSpeed: order.shippingSpeed,
    shipping: {
      name: order.shippingName,
      line1: order.shippingLine1,
      line2: order.shippingLine2,
      postalCode: order.shippingPostalCode,
      city: order.shippingCity,
      country: order.shippingCountry,
    },
    // Ce que l'écran de confirmation annonce. Les bornes viennent du palier
    // choisi tant que l'imprimeur n'a pas dit mieux.
    pageCount: order.pageCount,
    coverImageUrl: order.coverImageUrl,
    estimatedMinDays: order.estimatedMinDays,
    estimatedMaxDays: order.estimatedMaxDays,
    // Le prix figé, tel qu'il a été accepté. `null` sur les commandes d'avant
    // la tarification — l'app le lit comme « pas de montant à afficher »
    // plutôt que comme zéro.
    total: order.amountCents === null ? null : euros(order.amountCents),
    copyOptions: (order.copyOptions ?? [])
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((copy) => ({
        position: copy.position,
        decorationsEnabled: copy.decorationsEnabled,
        quizEnabled: copy.quizEnabled,
        freeZonesEnabled: copy.freeZonesEnabled,
        crosswordEnabled: copy.crosswordEnabled,
      })),
    notifyByWhatsApp: order.notifyByWhatsApp,
    whatsappPhone: order.whatsappPhone,
    trackingUrl: order.trackingUrl,
    error: order.error,
    createdAt: order.createdAt.toISOString(),
    updatedAt: order.updatedAt.toISOString(),
  };
}

/**
 * Le récapitulatif de l'étape 5, tel que l'app le dessine : deux groupes qui
 * portent chacun leur sous-total, les déductions, puis le net à payer.
 *
 * **L'app n'additionne rien.** Elle reçoit des montants déjà calculés et les
 * met en page — voir `services/printPricing.ts`.
 */
export function serializeOrderQuote(quote: PrintQuote) {
  return {
    bookTitle: quote.bookTitle,
    pageCount: quote.pageCount,
    copies: quote.copies,
    shippingSpeed: quote.speed,
    unitPrice: euros(quote.unitCents),
    book: {
      // **Une seule ligne, et le prix ne dépend que des pages.** Les trois
      // lignes de matière d'avant laissaient croire à trois options ; elles
      // descendent dans `specifications`, sous le prix, où elles décrivent le
      // produit au lieu de le facturer.
      lines: [
        {
          id: "book",
          label: `Carnet · ${quote.pageCount} pages`,
          detail: null,
          amount: euros(quote.unitCents),
        },
      ],
      subtotal: euros(quote.unitCents),
    },
    specifications: quote.specifications,
    fulfilment: {
      lines: [
        {
          id: "copies",
          label: "Exemplaires",
          detail: `x${quote.copies}`,
          amount: euros(quote.itemsCents),
        },
        {
          id: "shipping",
          label: quote.speed === "express" ? "Livraison Express" : "Livraison Standard",
          detail: null,
          amount: euros(quote.shippingCents),
        },
      ],
      subtotal: euros(quote.dueCents),
    },
    deductions: quote.deductions.map((deduction) => ({
      id: deduction.id,
      label: deduction.label,
      // Positif : c'est l'app qui pose le signe moins, comme elle pose l'euro.
      amount: euros(deduction.amountCents),
    })),
    total: euros(quote.totalCents),
    estimatedMinDays: quote.estimatedDays.min,
    estimatedMaxDays: quote.estimatedDays.max,
  };
}
