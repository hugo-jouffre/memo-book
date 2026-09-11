import type {
  Account,
  AccountConnector,
  GalleryCategory,
  Memo,
  MemoMember,
  MemoStep,
  PaymentCard,
  PrintOrder,
  Showcase,
  Subscription,
} from "@prisma/client";
import { CONNECTOR_CATALOG } from "../services/connectorCatalog.js";

/**
 * Ce que les trois écrans « produit » reçoivent : l'accueil, un voyage, le
 * profil.
 *
 * Séparé de `serializers.ts`, qui sert les objets du pipeline (carnet, souvenir,
 * rendu). Ici, la forme suit **les modèles Swift** de `MemoBookCore` au champ
 * près : `HomeFeed`, `TripDetail`, `TravellerProfile`. Un champ renommé d'un
 * côté casse le décodage de l'autre, et c'est ce fichier qui les tient
 * ensemble.
 *
 * Deux règles apprises du décodeur Swift :
 *
 *  - **Un champ non optionnel doit toujours être présent.** `stats`,
 *    `companions`, `progress`, `address`, `subscription` n'ont pas de valeur
 *    par défaut au décodage : les omettre fait échouer tout l'écran, pas
 *    seulement la ligne concernée.
 *  - **`TripTransport` refuse une valeur inconnue**, contrairement à
 *    `TripStage` qui la tolère. On ne sérialise donc que les sept modes de
 *    l'énumération, ce que le type Prisma garantit déjà.
 */

/** Les montants voyagent en euros, arrondis au centime. La base, elle, ne connaît que des centimes entiers. */
function euros(cents: number): number {
  return Number((cents / 100).toFixed(2));
}

function iso(date: Date | null): string | null {
  return date?.toISOString() ?? null;
}

// ---------------------------------------------------------------------------
// Accueil
// ---------------------------------------------------------------------------

type MemoForTrip = Memo & {
  members?: (MemoMember & { account?: Account | null })[];
};

/** Une pastille de co-voyageur. Le nom affiché prime sur celui du compte : quelqu'un peut vouloir apparaître autrement sur un voyage donné. */
function serializeCompanion(member: MemoMember & { account?: Account | null }) {
  const account = member.account;
  const fromAccount = [account?.firstName, account?.lastName]
    .filter((part): part is string => Boolean(part?.trim()))
    .join(" ");

  return {
    id: member.id,
    name: member.displayName?.trim() || fromAccount || member.invitedEmail || "Co-voyageur",
    avatarUrl: account?.avatarUrl ?? null,
  };
}

export function serializeTrip(memo: MemoForTrip) {
  // Les co-voyageurs sont les *autres* : le propriétaire est déjà le titulaire
  // de l'écran, sa pastille sur sa propre couverture n'apprend rien. Il n'a
  // d'ailleurs pas de ligne dans `memo_members`, qui ne porte que les autres.
  const companions = (memo.members ?? [])
    .filter((member) => member.status !== "removed")
    .map(serializeCompanion);

  return {
    id: memo.id,
    title: memo.title,
    destination: memo.destinationName
      ? {
          name: memo.destinationName,
          countryCode: memo.destinationCountryCode,
          city: memo.destinationCity ?? null,
        }
      : null,
    stage: memo.stage,
    startDate: iso(memo.startDate),
    endDate: iso(memo.endDate),
    coverPhotoUrl: memo.coverPhotoUrl,
    stats: {
      dayCount: memo.dayCount,
      distanceKilometres: memo.distanceKilometres,
      photoCount: memo.photoCount,
    },
    companions,
    // Un voyage à venir n'a rien à remplir encore : une barre à zéro dirait le
    // contraire de ce qui est vrai.
    progress:
      memo.stage === "upcoming"
        ? null
        : {
            memoryCount: memo.memoryCount,
            pageCount: memo.pageCount,
            targetPageCount: memo.targetPageCount,
          },
    isPrintable: memo.isPrintable,
  };
}

// ---------------------------------------------------------------------------
// La galerie de la communauté
// ---------------------------------------------------------------------------

type MemoForGallery = Memo & {
  steps?: Pick<MemoStep, "destinationName" | "destinationCountryCode">[];
  categories?: { categoryId: string }[];
};

/**
 * Les pays d'un voyage, sans doublon, celui du carnet d'abord puis ceux de ses
 * étapes dans l'ordre.
 *
 * **Rien n'est stocké** : c'est `memos.destination*` et `memo_steps.destination*`
 * relus ensemble, donc une vérité de moins à tenir d'accord. C'est cette liste
 * qui décide du pictogramme de la carte — un seul pays donne son drapeau,
 * plusieurs donnent le globe.
 */
function galleryDestinations(memo: MemoForGallery) {
  const all = [
    { name: memo.destinationName, countryCode: memo.destinationCountryCode },
    ...(memo.steps ?? []).map((step) => ({
      name: step.destinationName,
      countryCode: step.destinationCountryCode,
    })),
  ];

  const seen = new Set<string>();
  const destinations: { name: string; countryCode: string | null }[] = [];

  for (const place of all) {
    if (!place.name) continue;
    // Le code pays fait foi quand il existe : « Italie » et « Italy » sont le
    // même pays, `IT` et `IT` aussi.
    const key = place.countryCode?.toUpperCase() ?? place.name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    destinations.push({ name: place.name, countryCode: place.countryCode });
  }

  return destinations;
}

/**
 * Une carte de l'écran « Exemples de carnets ».
 *
 * Volontairement **plus maigre** que `serializeTrip` : la galerie ne montre ni
 * compteurs, ni progression, ni co-voyageurs, et ses cartes ne s'ouvrent pas
 * encore. Servir un `Trip` complet exposerait le contenu de carnets qui ne sont
 * pas à celui qui regarde, pour des champs que l'écran n'affiche pas.
 */
export function serializeGalleryTrip(memo: MemoForGallery) {
  return {
    id: memo.id,
    title: memo.title,
    // La phrase déduite du voyage. `null` tant qu'aucun agent ne l'a écrite :
    // la carte n'affiche alors que son titre.
    subtitle: memo.gallerySummary,
    destinations: galleryDestinations(memo),
    coverPhotoUrl: memo.coverPhotoUrl,
    categoryIds: (memo.categories ?? []).map((link) => link.categoryId),
  };
}

export function serializeGalleryCategory(category: GalleryCategory) {
  return {
    id: category.id,
    slug: category.slug,
    name: category.name,
    iconKey: category.iconKey,
  };
}

export function serializeShowcase(showcase: Showcase) {
  return {
    title: showcase.title,
    subtitle: showcase.subtitle ?? "",
    imageUrl: showcase.imageUrl,
    destinationUrl: showcase.destinationUrl,
  };
}

export function serializeTraveller(account: Account) {
  return {
    id: account.id,
    // Le prénom porte la salutation de l'accueil. À défaut, la partie locale de
    // l'adresse vaut mieux qu'un « Bonjour  » avec un trou dedans.
    firstName: account.firstName?.trim() || account.email?.split("@")[0] || "voyageur",
    avatarUrl: account.avatarUrl,
    offeredSteps: account.offeredSteps,
    remainingSteps: account.remainingSteps,
  };
}

// ---------------------------------------------------------------------------
// Un voyage
// ---------------------------------------------------------------------------

type StepWithMembers = MemoStep & {
  entries?: { id: string }[];
};

export function serializeTripStep(
  step: StepWithMembers,
  companions: ReturnType<typeof serializeCompanion>[],
) {
  return {
    id: step.id,
    number: step.number,
    placeName: step.placeName,
    destination: step.destinationName
      ? { name: step.destinationName, countryCode: step.destinationCountryCode }
      : null,
    startDate: iso(step.startDate),
    endDate: iso(step.endDate),
    // Les compagnons d'une étape sont ceux du voyage tant que la présence n'est
    // pas suivie étape par étape. Mieux vaut la liste du voyage qu'une liste
    // vide, qui ferait croire que personne n'y était.
    companions,
    photoUrl: step.photoUrl,
    transport: step.transport,
  };
}

// ---------------------------------------------------------------------------
// Profil
// ---------------------------------------------------------------------------

type AccountForProfile = Account & {
  cards?: PaymentCard[];
  connectors?: AccountConnector[];
  subscriptions?: Subscription[];
  identities?: { provider: string }[];
};

type OrderForTracking = PrintOrder & { memo?: { coverPhotoUrl: string | null } | null };

/**
 * Les voyages du compte, réduits à ce que la carte de chiffres du profil
 * regarde. Le profil n'a pas besoin des couvertures ni des compagnons.
 */
export type TripForProfileStats = {
  id: string;
  stage: string;
  startDate: Date | null;
  endDate: Date | null;
};

/**
 * Combien de voyages, et lequel est en cours.
 *
 * **Rien de tout ça n'est stocké** : les deux se déduisent des carnets visibles
 * par le compte, à chaque lecture du profil. Une colonne `tripCount` serait une
 * seconde vérité à tenir d'accord avec `memos` à chaque création, suppression
 * ou invitation — pour un chiffre que seul cet écran affiche.
 *
 * Le voyage « en cours » est le plus récemment commencé de ceux qui le sont :
 * la même règle que l'accueil, qui met ce voyage-là en tête.
 */
function serializeProfileStats(trips: TripForProfileStats[]) {
  const ongoing = trips
    .filter((trip) => trip.stage === "ongoing")
    .sort((a, b) => (b.startDate?.getTime() ?? 0) - (a.startDate?.getTime() ?? 0))[0];

  return {
    tripCount: trips.length,
    currentTrip: ongoing
      ? { id: ongoing.id, startDate: iso(ongoing.startDate), endDate: iso(ongoing.endDate) }
      : null,
  };
}

/** Fourchette de livraison par défaut, quand l'imprimeur n'a rien annoncé. */
const DEFAULT_DELIVERY_DAYS = { min: 5, max: 10 } as const;

function serializeOrderTracking(order: OrderForTracking) {
  return {
    id: order.id,
    minimumDays: order.estimatedMinDays ?? DEFAULT_DELIVERY_DAYS.min,
    maximumDays: order.estimatedMaxDays ?? DEFAULT_DELIVERY_DAYS.max,
    copies: order.copies,
    pageCount: order.pageCount ?? 0,
    coverImageUrl: order.coverImageUrl ?? order.memo?.coverPhotoUrl ?? null,
  };
}

function serializeCard(card: PaymentCard) {
  return {
    id: card.id,
    // La ligne du profil affiche ce libellé : à défaut du nom donné par
    // l'utilisateur, la marque de la carte reste reconnaissable.
    label: card.label?.trim() || card.brand || "Carte",
    last4: card.last4,
  };
}

/**
 * Les connecteurs sont **le catalogue**, pas seulement ceux déjà branchés :
 * l'écran doit proposer les six, en montrant lesquels sont actifs.
 */
function serializeConnectors(linked: AccountConnector[]) {
  const byKey = new Map(linked.map((connector) => [connector.connectorKey, connector]));

  return CONNECTOR_CATALOG.map((definition) => ({
    id: definition.key,
    name: definition.name,
    promise: definition.promise,
    isEnabled: byKey.get(definition.key)?.isEnabled ?? false,
    logoAssetName: definition.logoAssetName,
  }));
}

export function serializeProfile(
  account: AccountForProfile,
  orders: OrderForTracking[],
  trips: TripForProfileStats[] = [],
) {
  const fullName =
    [account.firstName, account.lastName]
      .filter((part): part is string => Boolean(part?.trim()))
      .join(" ") ||
    account.email ||
    "Voyageur";

  const subscription = account.subscriptions?.[0];
  const defaultCard = account.cards?.find((card) => card.isDefault);

  return {
    fullName,
    email: account.email,
    // Décide d'une chose et d'une seule côté app : l'adresse ne se corrige pas.
    // Elle appartient au compte Apple ou Google.
    signInProvider: account.identities?.[0]?.provider ?? null,
    phoneNumber: account.phoneNumber,
    avatarUrl: account.avatarUrl,
    address: {
      street: account.addressLine1 ?? "",
      postalCode: account.addressPostalCode ?? "",
      city: account.addressCity ?? "",
      country: account.addressCountry ?? "",
    },
    wantsNewsletter: account.wantsNewsletter,
    walletBalance: euros(account.walletBalanceCents),
    cards: (account.cards ?? []).map(serializeCard),
    selectedCardId: defaultCard?.id ?? account.cards?.[0]?.id ?? null,
    connectors: serializeConnectors(account.connectors ?? []),
    subscription: {
      weeklyPrice: subscription ? euros(subscription.priceCents) : 0,
      isActive: subscription?.status === "active" || subscription?.status === "trialing",
    },
    orders: orders.map(serializeOrderTracking),
    // Le quota d'étapes offertes est **le même couple que sur l'accueil**, et
    // pour la même raison : c'est lui qui porte la pastille des deux écrans.
    // Nul pour un abonné, qui n'a rien à décompter.
    offeredSteps: account.offeredSteps,
    remainingSteps: account.remainingSteps,
    ...serializeProfileStats(trips),
  };
}

// ---------------------------------------------------------------------------
// Paramètres du voyage, cagnotte, aperçu du carnet
// ---------------------------------------------------------------------------
//
// Les trois écrans de « 🤖 Claude Import ». Même règle que ci-dessus : la forme
// suit `TripSettings`, `Wallet` et `BookPreview` de `MemoBookCore` au champ
// près.

type MemoForSettings = Memo & {
  members?: (MemoMember & { account?: Account | null })[];
  renders?: { id: string; pdfUrl?: string | null }[];
};

/**
 * Ce que l'écran des réglages d'un voyage montre.
 *
 * `walletBalanceCents` vient du **compte** et se passe en argument : la
 * cagnotte n'appartient pas au carnet, et lire le solde depuis le voyage
 * laisserait croire qu'il y en a un par voyage.
 */
export function serializeTripSettings(memo: MemoForSettings, walletBalanceCents: number) {
  return {
    tripId: memo.id,
    name: memo.title,
    walletBalance: euros(walletBalanceCents),
    startDate: iso(memo.startDate),
    endDate: iso(memo.endDate),
    narrationPace: memo.narrationPace,
    wantsNotifications: memo.notificationsEnabled,
    companions: (memo.members ?? []).map(serializeCompanion),
    theme: memo.theme,
    isPublicGallery: memo.isPublicGallery,
    // Le style se **résume** plutôt qu'il ne se détaille : la ligne dit
    // « Pointillés, cadres, etc. », l'écran de personnalisation dira le reste.
    // Rien n'est stocké — c'est une phrase déduite des réglages qui existent,
    // et une seconde vérité de moins à tenir d'accord.
    styleSummary: styleSummaryOf(memo),
    // Le connecteur Tricount pend du **compte**, pas du voyage : il n'y a rien
    // à lire ici tant que la liaison n'existe pas. `null` fait afficher
    // l'invitation à le relier, ce qui est l'état de tout le monde aujourd'hui.
    tricountLabel: null,
    // La couverture du voyage, pas une vignette du rendu : `renders` ne porte
    // qu'un PDF, et fabriquer une image de sa première page côté serveur
    // coûterait un rendu de plus pour une vignette de 56 pt.
    previewCoverUrl: memo.coverPhotoUrl,
    isPrintable: memo.isPrintable,
    customisation: serializeBookCustomisation(memo),
  };
}

/**
 * Les personnalisations du carnet — l'écran « Style du carnet ».
 *
 * Elles voyagent **avec les réglages** et non sur une route à elles : il y en a
 * un jeu par voyage, elles se lisent toujours avec lui, et un second appel ne
 * ferait qu'afficher l'écran en deux temps.
 */
export function serializeBookCustomisation(memo: Memo) {
  return {
    photoTextRatio: memo.photoTextRatio,
    targetPageCount: memo.targetPageCount,
    funFactsEnabled: memo.funFactsEnabled,
    rulesEnabled: memo.rulesEnabled,
    decorationQuota: memo.decorationQuota,
    fontTitle: memo.fontTitle,
    fontDisplay: memo.fontDisplay,
    fontHand: memo.fontHand,
    fontFacts: memo.fontFacts,
    quizEnabled: memo.quizEnabled,
    freeZonesEnabled: memo.freeZonesEnabled,
    crosswordEnabled: memo.crosswordEnabled,
    // Dérivé plutôt que stocké : une troisième vérité à tenir d'accord avec
    // `coverFront` et `coverBack` finirait par diverger.
    hasConfiguredCovers: memo.coverFront !== null && memo.coverBack !== null,
  };
}

/**
 * « Pointillés, cadres, etc. » — ce que les personnalisations donnent, en une
 * ligne.
 *
 * Les trois premiers réglages actifs, et « etc. » s'il en reste. Une phrase
 * complète serait illisible en bout de ligne, et une liste vide ne dirait pas
 * qu'il y a quelque chose à régler — d'où le repli.
 */
function styleSummaryOf(memo: Memo): string {
  const active = [
    memo.freeZonesEnabled ? "Pointillés" : null,
    memo.rulesEnabled ? "cadres" : null,
    memo.funFactsEnabled ? "anecdotes" : null,
    memo.quizEnabled ? "quiz" : null,
    memo.crosswordEnabled ? "mots croisés" : null,
  ].filter((label): label is string => label !== null);

  if (active.length === 0) return "Aucun décor";
  return active.length > 3 ? `${active.slice(0, 3).join(", ")}, etc.` : active.join(", ");
}

/**
 * Ce que coûte une page imprimée, en centimes.
 *
 * **Une constante et non une colonne** : c'est un prix catalogue, le même pour
 * tout le monde, et il n'a rien à faire dupliqué sur chaque carnet. Le jour où
 * il varie — par format, par pays — il deviendra une table de tarifs, pas une
 * colonne de `memos`.
 *
 * 89,90 € pour les 50 pages de la maquette, soit 1,798 € la page. Les frais
 * fixes de fabrication et de port sont dedans : un carnet de dix pages ne
 * coûte pas un cinquième d'un carnet de cinquante, et c'est un sujet à trancher
 * avec l'imprimeur avant d'encaisser quoi que ce soit. Signalé.
 */
const CENTS_PER_PAGE = 179.8;

/**
 * Les trois états du texte d'un souvenir. Le corrigé à la main d'abord, le
 * rédigé ensuite, la transcription brute en dernier — c'est l'ordre de
 * préférence de tout le pipeline.
 */
type EntryTextRow = {
  editedText?: string | null;
  redactedText?: string | null;
  transcript?: string | null;
};

function textOf(entry: EntryTextRow): string | undefined {
  return (entry.editedText ?? entry.redactedText ?? entry.transcript)?.trim() || undefined;
}

type WalletEntryRow = {
  id: string;
  amountCents: number;
  kind: string;
  label: string | null;
  createdAt: Date;
};

/**
 * La cagnotte d'un compte, lue depuis l'écran d'un voyage.
 *
 * `trip` est optionnel : on arrive aussi depuis le profil, où il n'y a pas de
 * carnet à financer — seulement un solde à consulter.
 */
export function serializeWallet(
  balanceCents: number,
  entries: WalletEntryRow[],
  trip: Pick<Memo, "title" | "destinationCity" | "targetPageCount" | "pageCount"> | null
) {
  return {
    balance: euros(balanceCents),
    // L'historique va du plus récent au plus ancien, et c'est **le serveur**
    // qui ordonne : l'app ne retrie pas, sinon deux écritures du même jour
    // changeraient de place d'un affichage à l'autre.
    entries: entries.map((entry) => ({
      id: entry.id,
      amount: euros(entry.amountCents),
      kind: entry.kind,
      label: entry.label,
      date: entry.createdAt.toISOString(),
    })),
    // La ville plutôt que le titre : « Finance ton carnet de Rome » se lit,
    // « Finance ton carnet de Rome entre amis » non.
    tripTitle: trip?.destinationCity ?? trip?.title ?? null,
    estimate: trip ? serializeWalletEstimate(trip) : null,
  };
}

/**
 * Ce que le carnet pèsera et ce qu'il coûtera, au rythme actuel.
 *
 * Une **estimation** et non un prix : le carnet n'est pas fini, et son nombre
 * de pages bouge à chaque souvenir raconté. Elle vise le nombre de pages
 * demandé par le voyageur (`targetPageCount`), pas ce qui est déjà composé —
 * annoncer le coût des deux pages actuelles ferait une promesse qu'on ne
 * tiendra pas.
 */
function serializeWalletEstimate(trip: Pick<Memo, "targetPageCount" | "pageCount">) {
  const pages = Math.max(trip.targetPageCount, trip.pageCount);
  return { pageCount: pages, cost: euros(Math.round(pages * CENTS_PER_PAGE)) };
}

type MemoForPreview = Memo & {
  renders?: { id: string; status: string; pdfUrl?: string | null }[];
  entries?: EntryTextRow[];
};

/** L'aperçu du carnet : le PDF composé, et de quoi le partager. */
export function serializeBookPreview(memo: MemoForPreview, publicBaseUrl: string) {
  const render = memo.renders?.[0];
  const excerpt = serializeExcerpt(memo.entries ?? []);

  return {
    memoId: memo.id,
    // Le titre du récit s'il s'en est donné un, celui du voyage sinon.
    title: memo.bookTitle?.trim() || memo.title,
    status: serializeRenderStatus(render?.status),
    pdfUrl: render?.pdfUrl ?? null,
    pageCount: memo.pageCount,
    // Nul tant que personne n'a demandé à partager : c'est un lien public.
    shareUrl: memo.shareSlug ? `${publicBaseUrl}/c/${memo.shareSlug}` : null,
    coverPhotoUrl: memo.coverPhotoUrl,
    tripDate: iso(memo.startDate),
    excerpt,
    // Les deux couvertures sont choisies quand les deux existent. Dérivé plutôt
    // que stocké : une troisième vérité à tenir d'accord avec `coverFront` et
    // `coverBack` finirait forcément par diverger.
    hasConfiguredCovers: memo.coverFront !== null && memo.coverBack !== null,
  };
}

/**
 * L'état du rendu, traduit pour l'app.
 *
 * Trois états seulement là où le pipeline en a plus : l'écran ne sait faire que
 * « ça compose », « c'est prêt », « ça a raté ». Tout ce qui n'est ni prêt ni
 * en échec est une attente — c'est le repli sûr, et il est aussi celui du
 * décodeur Swift.
 */
function serializeRenderStatus(status: string | undefined) {
  if (status === "ready") return { status: "ready" };
  if (status === "failed") {
    return { status: "failed", message: "La composition n’a pas abouti." };
  }
  return { status: "composing" };
}

/**
 * Les deux phrases de la carte de partage, prises **dans le récit**.
 *
 * Elles ne se saisissent pas et ne se stockent pas : ce sont les premières
 * lignes de ce qui a été rédigé. Le jour où un agent écrit un vrai chapeau, il
 * remplacera cette fonction sans toucher au contrat.
 */
function serializeExcerpt(entries: EntryTextRow[]) {
  const sentences = entries
    .map((entry) => textOf(entry))
    .filter((text): text is string => Boolean(text))
    .flatMap((text) => text.split(/(?<=[.!?…])\s+/))
    .map((sentence) => sentence.trim())
    .filter((sentence) => sentence.length > 20);

  if (sentences.length === 0) return null;
  return { quote: truncate(sentences[0]!, 90), detail: sentences[1] ? truncate(sentences[1], 120) : null };
}

/** Coupe sur un mot entier et pose une ellipse — jamais au milieu d'une syllabe. */
function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const lastSpace = cut.lastIndexOf(" ");
  return `${(lastSpace > max / 2 ? cut.slice(0, lastSpace) : cut).trimEnd()}…`;
}
