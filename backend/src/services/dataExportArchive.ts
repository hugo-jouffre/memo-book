import type { Prisma, PrismaClient } from "@prisma/client";
import { Readable, type PassThrough } from "node:stream";
import { ZipFile } from "yazl";
import type { Env } from "../env.js";
import {
  fileDay,
  fileStamp,
  frenchCount,
  frenchDate,
  frenchTime,
} from "../lib/frenchFormat.js";
import { visibleToAccount } from "./memoOwnership.js";
import type { MediaStorage } from "./storage.js";
import { contextVoiceOf } from "./tripContext.js";

/**
 * L'archive de « Exporter mes données » : ce qu'elle contient, et comment elle
 * s'écrit. La demande et le lien sont dans `dataExport.ts`.
 *
 * **Deux lecteurs, deux formes.** Une machine lit des JSON — c'est le « format
 * structuré, couramment utilisé et lisible par machine » de l'article 20 —,
 * une personne lit le récit de chaque voyage en texte simple et le LISEZ-MOI
 * qui dit ce qu'il y a où. Les médias partent tels qu'ils ont été envoyés.
 *
 * **Ce que l'archive contient** : tout ce qui est au compte, et les voyages
 * qu'il voit — les siens et ceux où il est co-voyageur, comme
 * `visibleToAccount`. Un voyage partagé est un récit commun : son export porte
 * les souvenirs et la conversation de tous, mais des autres voyageurs, rien
 * que leur prénom — ni adresse, ni téléphone, ni commandes.
 *
 * **Ce qu'elle ne contient jamais** : les empreintes de mot de passe et de
 * jetons (elles ne servent qu'ici, et à qui voudrait les casser), les jetons
 * d'accès des connecteurs (ce sont des clés de comptes ailleurs), les mises en
 * page intermédiaires du carnet (`renders.payload`, recalculées à chaque
 * aperçu).
 *
 * **Elle s'écrit au fil du téléchargement**, un fichier après l'autre : la
 * mémoire ne tient jamais plus de deux médias à la fois, quelle que soit la
 * taille de l'archive. Un fichier qui manque au stockage n'interrompt rien — il
 * est nommé dans le LISEZ-MOI, écrit en dernier pour cette raison.
 */

/** Un fichier de l'archive, avant d'être écrit. */
export type ArchiveFile =
  | { path: string; source: "text"; content: string }
  | {
      path: string;
      source: "storage";
      storageKey: string;
      /** Le poids, quand la base le connaît — pour annoncer la taille de l'archive. */
      bytes: number | null;
      modifiedAt: Date;
    }
  /** Un carnet en PDF, chez le service qui l'a composé. */
  | { path: string; source: "url"; url: string; modifiedAt: Date };

/** Ce que la page de téléchargement annonce avant qu'on appuie. */
export interface ExportSummary {
  trips: number;
  memories: number;
  photos: number;
  voiceNotes: number;
  books: number;
  /** Ce que pèsent les fichiers dont on connaît la taille : l'ordre de grandeur de l'archive. */
  knownBytes: number;
}

export interface ExportPlan {
  /** Le dossier racine de l'archive, qui nomme aussi le fichier téléchargé. */
  rootName: string;
  files: ArchiveFile[];
  summary: ExportSummary;
  /** Le LISEZ-MOI. Écrit en dernier : il nomme les fichiers qui n'ont pas pu suivre. */
  readme(missing: readonly string[]): string;
}

// ---------------------------------------------------------------------------
// Ce qu'on lit en base
// ---------------------------------------------------------------------------

const accountInclude = {
  identities: { orderBy: { createdAt: "asc" } },
  devices: { orderBy: { createdAt: "asc" } },
  sessions: { orderBy: { createdAt: "asc" } },
  passwordResets: { orderBy: { createdAt: "asc" } },
  dataExports: { orderBy: { createdAt: "asc" } },
  connectors: { orderBy: { createdAt: "asc" } },
  cards: { orderBy: { createdAt: "asc" } },
  walletEntries: { orderBy: { createdAt: "asc" } },
  subscriptions: {
    orderBy: { startedAt: "asc" },
    include: {
      memo: { select: { id: true, title: true } },
      transactions: { orderBy: { purchasedAt: "asc" } },
    },
  },
  feedbackResponses: {
    orderBy: { shownAt: "asc" },
    include: {
      campaign: { select: { key: true, title: true } },
      answers: { include: { question: { select: { prompt: true, kind: true, position: true } } } },
    },
  },
  printOrders: {
    orderBy: { createdAt: "asc" },
    include: {
      memo: { select: { id: true, title: true } },
      copyOptions: { orderBy: { position: "asc" } },
    },
  },
} satisfies Prisma.AccountInclude;

const memoInclude = {
  owner: { select: { id: true, firstName: true } },
  members: {
    where: { status: "active" },
    orderBy: { invitedAt: "asc" },
    include: { account: { select: { id: true, firstName: true } } },
  },
  steps: { orderBy: { number: "asc" } },
  expenses: { orderBy: { occurredAt: "asc" } },
  entries: {
    orderBy: { capturedAt: "asc" },
    include: { media: true, step: { select: { number: true } } },
  },
  chatMessages: {
    orderBy: { seq: "asc" },
    include: { account: { select: { firstName: true } } },
  },
  // Les PDF prêts, du plus récent au plus ancien : le premier est « le »
  // carnet, les autres ne servent qu'à retrouver ceux qui ont été commandés.
  renders: {
    where: { status: "ready", pdfUrl: { not: null } },
    orderBy: { createdAt: "desc" },
    select: { id: true, createdAt: true, pdfUrl: true },
  },
  coverPhotos: { orderBy: { createdAt: "asc" } },
} satisfies Prisma.MemoInclude;

type ExportedAccount = Prisma.AccountGetPayload<{ include: typeof accountInclude }>;
type ExportedMemo = Prisma.MemoGetPayload<{ include: typeof memoInclude }>;
type ExportedEntry = ExportedMemo["entries"][number];

// ---------------------------------------------------------------------------
// Le plan de l'archive
// ---------------------------------------------------------------------------

/**
 * Tout ce que l'archive contiendra, sans rien télécharger : les JSON et les
 * récits sont écrits, les médias seulement désignés. La page s'en sert pour
 * annoncer l'archive, le téléchargement pour l'écrire.
 */
export async function planDataExport(
  context: { prisma: PrismaClient; env: Pick<Env, "SHARE_PUBLIC_BASE_URL"> },
  accountId: string,
  now: Date = new Date(),
): Promise<ExportPlan> {
  const { prisma, env } = context;

  const account = await prisma.account.findUniqueOrThrow({
    where: { id: accountId },
    include: accountInclude,
  });
  const memos = await prisma.memo.findMany({
    where: visibleToAccount(accountId),
    orderBy: [{ startDate: "asc" }, { createdAt: "asc" }],
    include: memoInclude,
  });

  const rootName = `memobook-donnees-${fileDay(now)}`;
  const texts: ArchiveFile[] = [];
  const media: ArchiveFile[] = [];
  const books: ArchiveFile[] = [];
  const summary: ExportSummary = {
    trips: memos.length,
    memories: 0,
    photos: 0,
    voiceNotes: 0,
    books: 0,
    knownBytes: 0,
  };

  const text = (path: string, content: string) => {
    texts.push({ path: `${rootName}/${path}`, source: "text", content });
    summary.knownBytes += Buffer.byteLength(content);
  };
  const json = (path: string, value: unknown) => text(path, `${JSON.stringify(value, null, 2)}\n`);
  const stored = (path: string, storageKey: string, bytes: number | null, modifiedAt: Date) => {
    media.push({ path: `${rootName}/${path}`, source: "storage", storageKey, bytes, modifiedAt });
    if (bytes !== null) summary.knownBytes += bytes;
  };

  // --- Le compte -------------------------------------------------------------

  let profilePhoto: string | null = account.avatarUrl;
  if (account.avatarStorageKey) {
    profilePhoto = `photo-de-profil.${extensionOf(account.avatarStorageKey, "image/jpeg")}`;
    stored(profilePhoto, account.avatarStorageKey, null, account.updatedAt);
  }
  json("compte.json", accountDocument(account, profilePhoto));

  // --- Les voyages -----------------------------------------------------------

  memos.forEach((memo, index) => {
    const folder = `voyages/${String(index + 1).padStart(2, "0")}-${slug(memo.title, "voyage")}`;
    const isOwner = memo.ownerAccountId === accountId;

    const memoryFiles = new Map<string, string>();
    for (const entry of memo.entries) {
      summary.memories += 1;
      if (!entry.media) continue;

      // L'original d'abord : c'est ce que la personne a envoyé. La version
      // agrandie, quand il y en a une, est un travail de MemoBook.
      const original = entry.media.originalStorageKey;
      const key = original ?? entry.media.storageKey;
      const kind = entry.kind === "audio" ? "vocal" : entry.kind === "photo" ? "photo" : "media";
      const name = `souvenirs/${fileStamp(entry.capturedAt)}_${kind}_${entry.id.slice(0, 8)}.${extensionOf(key, entry.media.mimeType)}`;
      memoryFiles.set(entry.id, name);
      stored(`${folder}/${name}`, key, original ? null : entry.media.bytes, entry.capturedAt);

      if (entry.kind === "photo") summary.photos += 1;
      if (entry.kind === "audio") summary.voiceNotes += 1;
    }

    // Les vocaux du contexte du voyage ne sont pas des souvenirs : leur fichier
    // pend au message (`chat_messages.payload.contextVoice`).
    const voiceFiles = new Map<string, string>();
    for (const message of memo.chatMessages) {
      const voice = contextVoiceOf(message.payload);
      if (!voice) continue;
      const name = `conversation/${fileStamp(message.createdAt)}_vocal_${message.id.slice(0, 8)}.${extensionOf(voice.storageKey, voice.mimeType)}`;
      voiceFiles.set(message.id, name);
      stored(`${folder}/${name}`, voice.storageKey, null, message.createdAt);
      summary.voiceNotes += 1;
    }

    const coverFiles = memo.coverPhotos.map((photo) => {
      const name = `couvertures/${fileStamp(photo.createdAt)}_${photo.id.slice(0, 8)}.${extensionOf(photo.storageKey, photo.mimeType)}`;
      stored(`${folder}/${name}`, photo.storageKey, photo.bytes, photo.createdAt);
      return { file: name, addedAt: iso(photo.createdAt) };
    });

    // Le carnet : le dernier PDF composé, et ceux que **ce compte** a commandés
    // s'ils sont plus anciens — un livre imprimé est celui qu'on veut garder.
    const orderedRenderIds = new Set(
      account.printOrders
        .filter((order) => order.memoId === memo.id)
        .map((order) => order.renderId),
    );
    const bookFiles: { file: string; composedAt: string | null; orderedByYou: boolean }[] = [];
    memo.renders.forEach((render, renderIndex) => {
      const ordered = orderedRenderIds.has(render.id);
      if (renderIndex > 0 && !ordered) return;
      if (!render.pdfUrl) return;
      const name =
        renderIndex === 0 ? "carnet.pdf" : `carnet-commande-${fileDay(render.createdAt)}-${render.id.slice(0, 8)}.pdf`;
      books.push({ path: `${rootName}/${folder}/${name}`, source: "url", url: render.pdfUrl, modifiedAt: render.createdAt });
      bookFiles.push({ file: name, composedAt: iso(render.createdAt), orderedByYou: ordered });
      summary.books += 1;
    });

    json(`${folder}/voyage.json`, tripDocument(memo, {
      accountId,
      isOwner,
      shareBaseUrl: env.SHARE_PUBLIC_BASE_URL,
      coverFiles,
      bookFiles,
    }));
    json(
      `${folder}/souvenirs.json`,
      memo.entries.map((entry) => memoryDocument(entry, memoryFiles.get(entry.id) ?? null)),
    );
    json(
      `${folder}/conversation.json`,
      memo.chatMessages.map((message) => ({
        at: iso(message.createdAt),
        author:
          message.author === "memo"
            ? "memo"
            : message.accountId === accountId
              ? "you"
              : "coTraveller",
        name:
          message.author === "traveller" && message.accountId !== accountId
            ? (message.account?.firstName ?? null)
            : null,
        kind: message.kind,
        text: message.text,
        memoryId: message.entryId,
        memoryIds: entryIdsOf(message.payload),
        file: voiceFiles.get(message.id) ?? null,
      })),
    );
    text(`${folder}/recit.txt`, story(memo, memoryFiles));
  });

  // --- Ce qui pend au compte ---------------------------------------------------

  json("commandes.json", account.printOrders.map(orderDocument));
  json("cagnotte.json", {
    balanceCents: account.walletBalanceCents,
    currency: "EUR",
    movements: account.walletEntries.map((entry) => ({
      at: iso(entry.createdAt),
      kind: entry.kind,
      label: entry.label,
      amountCents: entry.amountCents,
      balanceAfterCents: entry.balanceAfterCents,
      orderId: entry.printOrderId,
    })),
  });
  json(
    "abonnements.json",
    account.subscriptions.map((subscription) => ({
      provider: subscription.provider,
      status: subscription.status,
      trip: subscription.memo,
      priceCents: subscription.priceCents,
      currency: subscription.currency,
      interval: subscription.interval,
      productId: subscription.productId,
      autoRenews: subscription.autoRenews,
      environment: subscription.environment,
      startedAt: iso(subscription.startedAt),
      renewsAt: iso(subscription.renewsAt),
      cancelledAt: iso(subscription.cancelledAt),
      cancellationReason: subscription.cancellationReason,
      payments: subscription.transactions.map((transaction) => ({
        purchasedAt: iso(transaction.purchasedAt),
        expiresAt: iso(transaction.expiresAt),
        priceCents: transaction.priceCents,
        currency: transaction.currency,
        environment: transaction.environment,
        revokedAt: iso(transaction.revokedAt),
      })),
    })),
  );
  json(
    "moyens-de-paiement.json",
    account.cards.map((card) => ({
      label: card.label,
      brand: card.brand,
      last4: card.last4,
      expMonth: card.expMonth,
      expYear: card.expYear,
      isDefault: card.isDefault,
      addedAt: iso(card.createdAt),
    })),
  );
  json(
    "connecteurs.json",
    account.connectors.map((connector) => ({
      connector: connector.connectorKey,
      enabled: connector.isEnabled,
      externalAccount: connector.externalAccountLabel,
      connectedAt: iso(connector.connectedAt),
      updatedAt: iso(connector.updatedAt),
    })),
  );
  json("connexions.json", {
    devices: account.devices.map((device) => ({
      platform: device.platform,
      firstSeenAt: iso(device.createdAt),
      lastSeenAt: iso(device.lastSeenAt),
    })),
    sessions: account.sessions.map((session) => ({
      openedAt: iso(session.createdAt),
      lastSeenAt: iso(session.lastSeenAt),
      expiresAt: iso(session.expiresAt),
    })),
    passwordResets: account.passwordResets.map((reset) => ({
      requestedAt: iso(reset.createdAt),
      expiresAt: iso(reset.expiresAt),
      usedAt: iso(reset.usedAt),
    })),
    dataExports: account.dataExports.map((dataExport) => ({
      requestedAt: iso(dataExport.createdAt),
      sentTo: dataExport.email,
      expiresAt: iso(dataExport.expiresAt),
      replacedAt: iso(dataExport.revokedAt),
      downloads: dataExport.downloadCount,
      lastDownloadedAt: iso(dataExport.lastDownloadedAt),
    })),
  });
  json(
    "avis.json",
    account.feedbackResponses.map((response) => ({
      survey: response.campaign,
      shownAt: iso(response.shownAt),
      timesShown: response.displayCount,
      submittedAt: iso(response.submittedAt),
      dismissedAt: iso(response.dismissedAt),
      appVersion: response.appVersion,
      answers: [...response.answers]
        .sort((a, b) => a.question.position - b.question.position)
        .map((answer) => ({
          question: answer.question.prompt,
          kind: answer.question.kind,
          text: answer.textValue,
          number: answer.numberValue,
          choice: answer.choiceKey,
        })),
    })),
  );

  return {
    rootName,
    files: [...texts, ...media, ...books],
    summary,
    readme: (missing) => readme(account.email, now, missing),
  };
}

// ---------------------------------------------------------------------------
// Les documents
// ---------------------------------------------------------------------------

function iso(date: Date | null | undefined): string | null {
  return date ? date.toISOString() : null;
}

function accountDocument(account: ExportedAccount, profilePhoto: string | null) {
  const hasAddress = [
    account.addressLine1,
    account.addressLine2,
    account.addressPostalCode,
    account.addressCity,
    account.addressCountry,
  ].some((part) => part);

  return {
    id: account.id,
    email: account.email,
    emailVerifiedAt: iso(account.emailVerifiedAt),
    firstName: account.firstName,
    lastName: account.lastName,
    phoneNumber: account.phoneNumber,
    birthDate: account.birthDate ? account.birthDate.toISOString().slice(0, 10) : null,
    gender: account.gender,
    newsletter: account.wantsNewsletter,
    postalAddress: hasAddress
      ? {
          line1: account.addressLine1,
          line2: account.addressLine2,
          postalCode: account.addressPostalCode,
          city: account.addressCity,
          country: account.addressCountry,
        }
      : null,
    profilePhoto,
    signIn: {
      hasPassword: account.passwordHash !== null,
      providers: account.identities.map((identity) => ({
        provider: identity.provider,
        email: identity.email,
        subject: identity.subject,
        linkedAt: iso(identity.createdAt),
      })),
    },
    wallet: { balanceCents: account.walletBalanceCents, currency: "EUR" },
    freeSteps:
      account.offeredSteps === null
        ? null
        : { offered: account.offeredSteps, remaining: account.remainingSteps },
    memoryAllowance: {
      plan: account.memoryPlan,
      used: account.memoryUsed,
      periodStart: iso(account.memoryPeriodStart),
    },
    paymentCustomerId: account.stripeCustomerId,
    welcomeScreenSeenAt: iso(account.welcomeScreenSeenAt),
    createdAt: iso(account.createdAt),
    updatedAt: iso(account.updatedAt),
  };
}

function tripDocument(
  memo: ExportedMemo,
  options: {
    accountId: string;
    isOwner: boolean;
    shareBaseUrl: string;
    coverFiles: { file: string; addedAt: string | null }[];
    bookFiles: { file: string; composedAt: string | null; orderedByYou: boolean }[];
  },
) {
  const { accountId } = options;

  return {
    id: memo.id,
    yourRole: options.isOwner ? "owner" : "coTraveller",
    title: memo.title,
    subtitle: memo.subtitle,
    bookTitle: memo.bookTitle,
    authors: memo.authors,
    theme: memo.theme,
    destination: {
      name: memo.destinationName,
      countryCode: memo.destinationCountryCode,
      city: memo.destinationCity,
    },
    startDate: iso(memo.startDate),
    endDate: iso(memo.endDate),
    stage: memo.stage,
    narrationPace: memo.narrationPace,
    accessCode: memo.accessCode,
    shareLink: memo.shareSlug ? `${options.shareBaseUrl}/c/${memo.shareSlug}` : null,
    gallery: { shared: memo.isPublicGallery, summary: memo.gallerySummary },
    notifications: {
      enabled: memo.notificationsEnabled,
      writingReminder: memo.notifyWritingReminder,
      newStory: memo.notifyNewStory,
      weeklyDigest: memo.notifyWeeklyDigest,
      tripEnd: memo.notifyTripEnd,
    },
    bookSettings: {
      targetPageCount: memo.targetPageCount,
      photoTextRatio: memo.photoTextRatio,
      funFacts: memo.funFactsEnabled,
      quiz: memo.quizEnabled,
      rules: memo.rulesEnabled,
      freeZones: memo.freeZonesEnabled,
      crossword: memo.crosswordEnabled,
      decorationQuota: memo.decorationQuota,
      fonts: {
        display: memo.fontDisplay,
        title: memo.fontTitle,
        hand: memo.fontHand,
        facts: memo.fontFacts,
      },
      coverFront: memo.coverFront,
      coverBack: memo.coverBack,
    },
    tripContext: memo.tripContext,
    coherenceSheet: memo.coherenceSheet,
    counters: {
      memories: memo.memoryCount,
      pages: memo.pageCount,
      days: memo.dayCount,
      kilometres: memo.distanceKilometres,
      photos: memo.photoCount,
    },
    // Des autres voyageurs, le prénom seul — et le lien que la rédaction a
    // déduit, puisqu'il dit qui ils sont pour toi.
    travellers: [
      {
        name: memo.owner.firstName,
        role: "owner",
        you: memo.owner.id === accountId,
        relationship: null,
        joinedAt: iso(memo.createdAt),
      },
      ...memo.members.map((member) => ({
        name: member.displayName ?? member.account?.firstName ?? member.handle,
        role: "coTraveller",
        you: member.accountId === accountId,
        relationship: member.role,
        joinedAt: iso(member.acceptedAt ?? member.invitedAt),
      })),
    ],
    steps: memo.steps.map((step) => ({
      number: step.number,
      place: step.placeName,
      destination: { name: step.destinationName, countryCode: step.destinationCountryCode },
      startDate: iso(step.startDate),
      endDate: iso(step.endDate),
      transport: step.transport,
    })),
    expenses: memo.expenses.map((expense) => ({
      amountCents: expense.amountCents,
      currency: expense.currency,
      label: expense.label,
      occurredAt: iso(expense.occurredAt),
      place: expense.placeLabel,
      source: expense.source,
    })),
    coverPhotos: options.coverFiles,
    books: options.bookFiles,
    files: { story: "recit.txt", memories: "souvenirs.json", conversation: "conversation.json" },
    createdAt: iso(memo.createdAt),
    updatedAt: iso(memo.updatedAt),
  };
}

/** Le texte qui entre dans le carnet : la correction au clavier fait autorité. */
function finalText(entry: ExportedEntry): string | null {
  return entry.editedText ?? entry.redactedText ?? entry.transcript ?? null;
}

function memoryDocument(entry: ExportedEntry, file: string | null) {
  return {
    id: entry.id,
    kind: entry.kind,
    capturedAt: iso(entry.capturedAt),
    place: entry.placeLabel,
    step: entry.step?.number ?? null,
    title: entry.suggestedTitle,
    text: {
      final: finalText(entry),
      transcript: entry.transcript,
      writtenByMemo: entry.redactedText,
      writtenAt: iso(entry.redactedAt),
      writtenWith: entry.redactionModel,
      editedByYou: entry.editedText,
      editedAt: iso(entry.editedAt),
    },
    funFact: entry.funFact ? { title: entry.funFactTitle, text: entry.funFact } : null,
    weather: entry.weatherKey,
    quiz: entry.quizQuestion
      ? { question: entry.quizQuestion, answers: entry.quizAnswers, answerIndex: entry.quizAnswerIndex }
      : null,
    validatedAt: iso(entry.validatedAt),
    status: entry.status,
    file,
    media: entry.media
      ? {
          mimeType: entry.media.mimeType,
          bytes: entry.media.originalStorageKey ? null : entry.media.bytes,
          durationSeconds: entry.media.durationSeconds,
        }
      : null,
    photo:
      entry.kind === "photo"
        ? {
            widthPx: entry.photoWidthPx,
            heightPx: entry.photoHeightPx,
            verdict: entry.photoVerdict,
            sharpness: entry.photoSharpness,
            exposure: entry.photoExposure,
            tapeCorner: entry.tapeCorner,
            focus: entry.focusX !== null && entry.focusY !== null ? { x: entry.focusX, y: entry.focusY } : null,
          }
        : null,
    insights: entry.insights,
    createdAt: iso(entry.createdAt),
  };
}

function orderDocument(order: ExportedAccount["printOrders"][number]) {
  return {
    id: order.id,
    trip: order.memo,
    status: order.status,
    copies: order.copies,
    copyOptions: order.copyOptions.map((copy) => ({
      position: copy.position,
      decorations: copy.decorationsEnabled,
      quiz: copy.quizEnabled,
      freeZones: copy.freeZonesEnabled,
      crossword: copy.crosswordEnabled,
    })),
    shippingSpeed: order.shippingSpeed,
    shippingAddress: {
      name: order.shippingName,
      line1: order.shippingLine1,
      line2: order.shippingLine2,
      postalCode: order.shippingPostalCode,
      city: order.shippingCity,
      country: order.shippingCountry,
    },
    whatsappTracking: order.notifyByWhatsApp ? order.whatsappPhone : null,
    pageCount: order.pageCount,
    amounts: {
      itemsCents: order.itemsCents,
      shippingCents: order.shippingCents,
      walletAppliedCents: order.walletAppliedCents,
      totalCents: order.amountCents,
      refundedCents: order.refundedCents,
      currency: "EUR",
    },
    paymentReference: order.stripePaymentIntentId,
    delivery: {
      estimatedMinDays: order.estimatedMinDays,
      estimatedMaxDays: order.estimatedMaxDays,
      carrier: order.carrier,
      trackingUrl: order.trackingUrl,
    },
    submittedAt: iso(order.submittedAt),
    shippedAt: iso(order.shippedAt),
    deliveredAt: iso(order.deliveredAt),
    createdAt: iso(order.createdAt),
    updatedAt: iso(order.updatedAt),
  };
}

/** Les souvenirs d'une bulle de photos (`payload.entryIds`), relus défensivement. */
function entryIdsOf(payload: Prisma.JsonValue): string[] | null {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return null;
  const ids = (payload as Record<string, unknown>)["entryIds"];
  if (!Array.isArray(ids)) return null;
  const strings = ids.filter((id): id is string => typeof id === "string");
  return strings.length > 0 ? strings : null;
}

// ---------------------------------------------------------------------------
// Le récit, et le LISEZ-MOI
// ---------------------------------------------------------------------------

const KIND_LABELS = { audio: "vocal", text: "écrit", photo: "photo" } as const;

/**
 * Le voyage tel qu'on le relit : un jour après l'autre, chaque souvenir avec
 * le texte qui entre dans le carnet. Du texte simple, qui s'ouvre partout — le
 * détail des trois versions d'un texte est dans `souvenirs.json`.
 */
function story(memo: ExportedMemo, memoryFiles: Map<string, string>): string {
  const lines: string[] = [memo.title];
  if (memo.bookTitle && memo.bookTitle !== memo.title) lines.push(`« ${memo.bookTitle} »`);

  const when =
    memo.startDate && memo.endDate
      ? `Du ${frenchDate(memo.startDate)} au ${frenchDate(memo.endDate)}`
      : memo.startDate
        ? `À partir du ${frenchDate(memo.startDate)}`
        : null;
  const where = [memo.destinationCity, memo.destinationName].filter(Boolean).join(", ");
  const heading = [when, where].filter(Boolean).join(" · ");
  if (heading) lines.push(heading);

  const travellers = [
    memo.owner.firstName,
    ...memo.members.map((member) => member.displayName ?? member.account?.firstName ?? member.handle),
  ].filter((name): name is string => Boolean(name));
  if (travellers.length > 1) lines.push(`Voyageurs : ${travellers.join(", ")}`);

  lines.push(
    "",
    "Le récit du voyage, souvenir par souvenir, avec le texte qui entre dans le carnet. Les heures sont celles de Paris. Le détail — ta transcription, le texte de MEMO, tes corrections — est dans souvenirs.json.",
  );

  if (memo.entries.length === 0) {
    lines.push("", "Aucun souvenir raconté pour l’instant.");
    return `${lines.join("\n")}\n`;
  }

  let currentDay = "";
  for (const entry of memo.entries) {
    const day = frenchDate(entry.capturedAt, { weekday: true });
    if (day !== currentDay) {
      currentDay = day;
      lines.push("", "", day.charAt(0).toUpperCase() + day.slice(1), "─".repeat(day.length));
    }

    const header = [frenchTime(entry.capturedAt), entry.placeLabel, KIND_LABELS[entry.kind]]
      .filter(Boolean)
      .join(" · ");
    lines.push("", header);
    if (entry.suggestedTitle) lines.push(entry.suggestedTitle);
    const body = finalText(entry);
    if (body) lines.push(body.trim());
    const file = memoryFiles.get(entry.id);
    if (file) lines.push(`→ ${file}`);
  }

  return `${lines.join("\n")}\n`;
}

function readme(email: string | null, now: Date, missing: readonly string[]): string {
  const lines = [
    "MemoBook — tes données",
    "══════════════════════",
    "",
    `Archive composée le ${frenchDate(now)} à ${frenchTime(now)} (heure de Paris)${email ? `, pour le compte ${email}` : ""}.`,
    "",
    "C’est la copie de tout ce que MemoBook garde de toi au moment du téléchargement : ton droit d’accès et ton droit à la portabilité (RGPD, articles 15 et 20). Les fichiers .json se lisent avec n’importe quel éditeur de texte et s’importent ailleurs ; chaque voyage a aussi son récit, en texte simple.",
    "",
    "",
    "Ce que contient l’archive",
    "─────────────────────────",
    "",
    "compte.json               Ton compte : identité, coordonnées, adresse, moyens de connexion, cagnotte, réglages.",
    "photo-de-profil.*         Ta photo de profil, si tu en as envoyé une.",
    "voyages/                  Un dossier par voyage — les tiens, et ceux où tu es co-voyageur :",
    "  voyage.json             le voyage, ses réglages, ses étapes, ses dépenses, ses voyageurs ;",
    "  recit.txt               le récit, lisible, souvenir par souvenir ;",
    "  souvenirs.json          chaque souvenir : ta transcription, le texte de MEMO, tes corrections ;",
    "  souvenirs/              tes photos et tes vocaux, tels que tu les as envoyés ;",
    "  conversation.json       la conversation avec MEMO ;",
    "  conversation/           les vocaux du contexte du voyage ;",
    "  couvertures/            les photos importées pour la couverture ;",
    "  carnet*.pdf             le dernier carnet composé, et ceux que tu as commandés.",
    "commandes.json            Tes commandes de carnets imprimés.",
    "cagnotte.json             Les mouvements de ta cagnotte.",
    "abonnements.json          Tes abonnements, et chaque semaine payée.",
    "moyens-de-paiement.json   Tes cartes : la marque, les quatre derniers chiffres, l’échéance. Jamais le numéro : nous ne l’avons pas.",
    "connecteurs.json          Les applications que tu as branchées.",
    "connexions.json           Tes appareils, tes sessions, tes demandes de mot de passe et d’export.",
    "avis.json                 Tes réponses à nos questionnaires.",
    "",
    "",
    "Les formats",
    "───────────",
    "",
    "- Du texte en UTF-8.",
    "- Dans les JSON, les dates sont en ISO 8601, en temps universel (UTC). Dans les récits, à l’heure de Paris.",
    "- Les montants sont en centimes d’euro : 1990 veut dire 19,90 €.",
    "",
    "",
    "Ce qui n’y est pas, et pourquoi",
    "──────────────────────────────",
    "",
    "- Ton mot de passe et tes jetons de connexion : nous n’en gardons qu’une empreinte, qui ne sert à rien hors de MemoBook.",
    "- Les clés d’accès des connecteurs : ce sont des clés de tes comptes chez d’autres services.",
    "- Les comptes de tes co-voyageurs : d’un voyage partagé, l’archive contient le récit commun et leurs prénoms, rien d’autre.",
    "- Les mises en page intermédiaires du carnet : elles se recalculent à chaque aperçu.",
  ];

  if (missing.length > 0) {
    lines.push(
      "",
      "",
      "Fichiers absents",
      "────────────────",
      "",
      `${frenchCount(missing.length, "fichier n’a", "fichiers n’ont")} pas pu être joint${missing.length > 1 ? "s" : ""} au moment du téléchargement. Relance-le depuis le lien de l’e-mail ; s’il manque encore quelque chose, réponds à l’e-mail qui t’a envoyé le lien, et on te le fera parvenir.`,
      "",
      ...missing.map((path) => `- ${path.split("/").slice(1).join("/")}`),
    );
  }

  lines.push(
    "",
    "",
    "Tes autres droits",
    "─────────────────",
    "",
    "Rectifier, effacer, t’opposer, limiter : depuis l’app (Profil), ou en répondant à l’e-mail qui t’a donné ce lien. Nous répondons sous un mois.",
    "",
  );

  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Les noms de fichiers
// ---------------------------------------------------------------------------

/**
 * `Rome 2026 — Trastevere !` → `rome-2026-trastevere`. Rien que de l'ASCII :
 * l'outil de décompression de Windows lit encore mal les noms accentués d'un
 * ZIP, et un dossier au nom cassé ne s'ouvre plus.
 */
export function slug(value: string, fallback: string): string {
  const ascii = value
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40)
    .replace(/-+$/, "");
  return ascii || fallback;
}

const EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/heic": "heic",
  "image/heif": "heif",
  "image/webp": "webp",
  "audio/mp4": "m4a",
  "audio/m4a": "m4a",
  "audio/x-m4a": "m4a",
  "audio/aac": "aac",
  "audio/mpeg": "mp3",
  "audio/wav": "wav",
  "audio/x-wav": "wav",
  "audio/webm": "webm",
  "application/pdf": "pdf",
};

/** L'extension de la clé de stockage, sinon celle du type MIME. */
function extensionOf(storageKey: string, mimeType: string): string {
  const fromKey = /\.([a-z0-9]{2,5})$/i.exec(storageKey)?.[1];
  return fromKey?.toLowerCase() ?? EXTENSIONS[mimeType.toLowerCase()] ?? "bin";
}

// ---------------------------------------------------------------------------
// L'écriture
// ---------------------------------------------------------------------------

export interface ArchiveSources {
  storage: Pick<MediaStorage, "get">;
  /** Télécharge un carnet en PDF. `fetch` en vrai ; un double dans les tests. */
  fetchBook(url: string, signal: AbortSignal): Promise<Buffer>;
  /** Où dire qu'un fichier n'a pas suivi, ou que l'écriture a cassé. */
  onProblem(details: object, message: string): void;
}

/** Un média qui ne répond pas en une minute ne retient pas toute l'archive. */
const FETCH_TIMEOUT_MS = 60_000;

/** Les morceaux qu'on pousse dans le ZIP : petits, pour que la contre-pression morde. */
const CHUNK_BYTES = 64 * 1024;

/**
 * Le ZIP, en flux. À envoyer tel quel en réponse : il s'écrit au rythme où on
 * le lit, un fichier après l'autre, et s'arrête si `signal` est levé — le
 * client est parti, inutile d'aller chercher le reste au stockage.
 *
 * Les médias partent **sans recompression** : un JPEG ou un M4A ne gagne rien
 * au Deflate, et le processeur de l'API a mieux à faire. Les JSON et les
 * récits, eux, se compressent bien.
 */
export function streamArchive(
  plan: ExportPlan,
  sources: ArchiveSources,
  signal: AbortSignal,
): Readable {
  const zip = new ZipFile();
  const output = zip.outputStream as PassThrough;

  // Sans écouteur, une erreur de yazl tuerait le process : elle remonte au
  // flux, que Fastify ferme proprement.
  zip.on("error", (error: Error) => {
    sources.onProblem({ err: error }, "L’archive d’export s’est interrompue");
    output.destroy(error);
  });
  signal.addEventListener("abort", () => output.destroy(), { once: true });

  writeEntries(zip, plan, sources, signal).catch((error: unknown) => {
    sources.onProblem({ err: error }, "L’archive d’export s’est interrompue");
    output.destroy(error instanceof Error ? error : new Error(String(error)));
  });

  return output;
}

async function writeEntries(
  zip: ZipFile,
  plan: ExportPlan,
  sources: ArchiveSources,
  signal: AbortSignal,
): Promise<void> {
  const missing: string[] = [];

  const load = async (file: ArchiveFile): Promise<Buffer | null> => {
    try {
      switch (file.source) {
        case "text":
          return Buffer.from(file.content, "utf8");
        case "storage":
          return await withTimeout(sources.storage.get(file.storageKey), FETCH_TIMEOUT_MS);
        case "url": {
          if (!/^https?:\/\//.test(file.url)) return null;
          return await sources.fetchBook(file.url, AbortSignal.any([signal, AbortSignal.timeout(FETCH_TIMEOUT_MS)]));
        }
      }
    } catch (error) {
      sources.onProblem({ err: error, file: file.path }, "Un fichier n’a pas pu rejoindre l’archive d’export");
      return null;
    }
  };

  // Un média d'avance : on va le chercher pendant que le précédent part. Pas
  // un carnet, qui peut peser cent mégaoctets — il attend son tour.
  const prefetchable = (file: ArchiveFile | undefined) => file !== undefined && file.source !== "url";

  let ahead: Promise<Buffer | null> | null = null;
  for (let index = 0; index < plan.files.length; index += 1) {
    if (signal.aborted) return;
    const file = plan.files[index]!;
    const body = await (ahead ?? load(file));
    ahead = prefetchable(plan.files[index + 1]) ? load(plan.files[index + 1]!) : null;

    if (body === null) {
      missing.push(file.path);
      continue;
    }
    await addEntry(zip, file.path, body, entryOptions(file), signal);
  }
  if (signal.aborted) return;

  const readme = Buffer.from(plan.readme(missing), "utf8");
  await addEntry(zip, `${plan.rootName}/LISEZ-MOI.txt`, readme, { compress: true, mtime: new Date() }, signal);
  zip.end();
}

/** Les textes se compressent ; les médias gardent la date où ils ont été pris. */
function entryOptions(file: ArchiveFile): { compress: boolean; mtime: Date } {
  return file.source === "text"
    ? { compress: true, mtime: new Date() }
    : { compress: false, mtime: file.modifiedAt };
}

/**
 * Pose un fichier dans le ZIP et attend qu'il soit **passé dans le flux** —
 * c'est-à-dire lu par le client, à la contre-pression près. C'est ce qui
 * borne la mémoire : on ne va chercher le suivant qu'une fois celui-ci parti.
 */
function addEntry(
  zip: ZipFile,
  path: string,
  body: Buffer,
  options: { compress: boolean; mtime: Date },
  signal: AbortSignal,
): Promise<void> {
  return new Promise((resolve) => {
    if (signal.aborted) return resolve();
    const stop = () => resolve();
    signal.addEventListener("abort", stop, { once: true });

    zip.addReadStreamLazy(
      path,
      { ...options, size: body.length },
      (callback) => {
        const stream = Readable.from(chunksOf(body), { objectMode: false });
        stream.once("end", () => {
          signal.removeEventListener("abort", stop);
          resolve();
        });
        callback(null, stream);
      },
    );
  });
}

function* chunksOf(body: Buffer): Generator<Buffer> {
  for (let offset = 0; offset < body.length; offset += CHUNK_BYTES) {
    yield body.subarray(offset, offset + CHUNK_BYTES);
  }
}

function withTimeout<T>(promise: Promise<T>, milliseconds: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`Pas de réponse en ${milliseconds / 1000} s`)), milliseconds);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
