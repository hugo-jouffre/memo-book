import type {
  Account,
  AccountConnector,
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

/** Une pastille de compagnon. Le nom affiché prime sur celui du compte : quelqu'un peut vouloir apparaître autrement sur un voyage donné. */
function serializeCompanion(member: MemoMember & { account?: Account | null }) {
  const account = member.account;
  const fromAccount = [account?.firstName, account?.lastName]
    .filter((part): part is string => Boolean(part?.trim()))
    .join(" ");

  return {
    id: member.id,
    name: member.displayName?.trim() || fromAccount || member.invitedEmail || "Invité",
    avatarUrl: account?.avatarUrl ?? null,
  };
}

export function serializeTrip(memo: MemoForTrip) {
  // Les compagnons sont les *autres* : le propriétaire est déjà le titulaire de
  // l'écran, sa pastille sur sa propre couverture n'apprend rien.
  const companions = (memo.members ?? [])
    .filter((member) => member.role !== "owner" && member.status !== "removed")
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

export function serializeProfile(account: AccountForProfile, orders: OrderForTracking[]) {
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
  };
}
