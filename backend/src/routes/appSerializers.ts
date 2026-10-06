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
  TripTheme,
} from "@prisma/client";
import { CONNECTOR_CATALOG } from "../services/connectorCatalog.js";
import { serializeDailyCredit, type DailyCredit } from "../services/dailyCredit.js";
import { unitPriceCents } from "../services/printPricing.js";
import { findShippingCountry, SHIPPING_COUNTRIES } from "../services/shippingCountries.js";
import { SUBSCRIPTION_MONTHLY_CENTS } from "../services/subscriptionCatalog.js";
import { grantsUnlimitedAccess } from "../services/subscriptions.js";
import { avatarUrlOf } from "../services/avatars.js";
import { effectiveGender } from "../services/genderInference.js";
import { effectiveStage } from "../services/tripStage.js";

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

/** Le nom affiché prime sur celui du compte : quelqu'un peut vouloir apparaître autrement sur un voyage donné. */
function companionName(member: MemoMember & { account?: Account | null }) {
  const account = member.account;
  const fromAccount = [account?.firstName, account?.lastName]
    .filter((part): part is string => Boolean(part?.trim()))
    .join(" ");

  return member.displayName?.trim() || fromAccount || member.invitedEmail || "Co-voyageur";
}

/**
 * Une pastille de co-voyageur.
 *
 * `role`, `isOwner` et `isPending` sont arrivés avec la feuille « Inviter un
 * proche » : elle liste le voyage entier, propriétaire compris, et ses deux
 * actions au balayage dépendent de l'état — on ne retire pas le propriétaire, on
 * ne renvoie pas de lien à quelqu'un qui raconte déjà.
 */
function serializeCompanion(member: MemoMember & { account?: Account | null }) {
  return {
    id: member.id,
    name: companionName(member),
    avatarUrl: member.account ? avatarUrlOf(member.account) : null,
    role: member.role ?? null,
    isOwner: false,
    // `invited` : le lien est parti, personne n'est entré. `active` veut dire
    // que le compte a rejoint le voyage.
    isPending: member.status === "invited",
  };
}

/**
 * La ligne du propriétaire, en tête de la liste des co-voyageurs.
 *
 * **Il n'a pas de ligne dans `memo_members`** — cette table ne porte que les
 * autres —, donc il se fabrique ici. La feuille le montre parce que c'est ce
 * qui fait lire la liste comme celle du voyage entier ; l'app le retire là où
 * elle compte les invités (`TripSettings.guests`).
 */
function serializeOwner(owner: Account) {
  const fullName = [owner.firstName, owner.lastName]
    .filter((part): part is string => Boolean(part?.trim()))
    .join(" ");

  return {
    id: owner.id,
    name: fullName || owner.email || "Moi",
    avatarUrl: avatarUrlOf(owner),
    role: null,
    isOwner: true,
    isPending: false,
  };
}

/**
 * Une carte de voyage, **vue par quelqu'un**.
 *
 * `viewerAccountId` : celui qui lit. Il décide de `canDelete` (T233, Hugo
 * 06/10/2026) — supprimer un voyage n'appartient qu'à son propriétaire, et un
 * co-voyageur ne doit même pas voir l'option : il la voyait, et le serveur lui
 * répondait 404.
 *
 * `dailyCredit` n'est passé que pour un voyage **en cours** de l'accueil :
 * c'est le crédit que vise le vocal de l'accueil, et la carte le porte pour
 * que la feuille d'enregistrement sache où elle en est sans un appel de plus
 * (03/10/2026).
 */
export function serializeTrip(
  memo: MemoForTrip,
  options: { viewerAccountId: string; dailyCredit?: DailyCredit },
) {
  const { dailyCredit } = options;
  // Les co-voyageurs sont les *autres* : le propriétaire est déjà le titulaire
  // de l'écran, sa pastille sur sa propre couverture n'apprend rien. Il n'a
  // d'ailleurs pas de ligne dans `memo_members`, qui ne porte que les autres.
  const companions = (memo.members ?? [])
    .filter((member) => member.status !== "removed")
    .map(serializeCompanion);

  // **L'état se lit sur les dates, pas sur la colonne** : un voyage fini hier
  // restait « en cours » tant que personne ne le rouvrait. Voir
  // `services/tripStage.ts`.
  const stage = effectiveStage(memo);

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
    stage,
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
      stage === "upcoming"
        ? null
        : {
            memoryCount: memo.memoryCount,
            pageCount: memo.pageCount,
            targetPageCount: memo.targetPageCount,
          },
    isPrintable: memo.isPrintable,
    ...(dailyCredit ? { dailyCredit: serializeDailyCredit(dailyCredit) } : {}),
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

/** Un thème de « Contexte de ton voyage » — au nom près de `TripTheme` côté Swift. */
export function serializeTripTheme(theme: TripTheme) {
  return {
    id: theme.id,
    slug: theme.slug,
    emoji: theme.emoji,
    name: theme.name,
    isOther: theme.isOther,
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

type AccountWithSubscriptions = Account & { subscriptions?: Subscription[] };

/**
 * `trips` : les voyages que l'accueil montre. Ils disent s'il en reste un en
 * cours — ce qui décide du rappel `subscriptionOutlivesTrip`.
 *
 * **Plus de pastille d'étapes** (Hugo, 03/10/2026) : `offeredSteps` et
 * `remainingSteps` sont **omis**, jamais rendus à 3 ou à 0 — une app installée
 * lit un champ nul comme « abonné », et c'est la lecture la plus juste de ce
 * qui est devenu un crédit du jour par voyage.
 */
export function serializeTraveller(
  account: AccountWithSubscriptions,
  trips: { endDate: Date | null }[] = [],
  now: Date = new Date(),
) {
  const subscriptions = account.subscriptions ?? [];
  return {
    id: account.id,
    // Le prénom porte la salutation de l'accueil. À défaut, la partie locale de
    // l'adresse vaut mieux qu'un « Bonjour  » avec un trou dedans.
    firstName: account.firstName?.trim() || account.email?.split("@")[0] || "voyageur",
    avatarUrl: avatarUrlOf(account),
    // **Déduit, pas stocké** : la période payée du dernier abonnement, si elle
    // vient de s'achever. C'est ce qui permet à l'accueil d'ouvrir l'alerte
    // système « ton abonnement s'est arrêté » — voir `justEndedSubscription`.
    subscriptionEndedOn: iso(justEndedSubscription(subscriptions)),
    // **Le rappel de fin de voyage** (01/10/2026) : l'abonnement App Store se
    // renouvelle encore alors qu'aucun voyage ne court. Apple ne laisse pas
    // l'app le couper à la place de la personne ; l'accueil le lui propose,
    // en un geste. L'abonnement ne s'arrête jamais de lui-même.
    subscriptionOutlivesTrip: outlivesEveryTrip(subscriptions, trips),
    // Raconte-t-il sans limite ? La même règle que le crédit du jour
    // (`grantsUnlimitedAccess`) : le verrou du micro et le paywall de l'accueil
    // en dépendent.
    isUnlimited: subscriptions.some((entry) => grantsUnlimitedAccess(entry, now)),
    // A-t-il déjà été abonné ? C'est ce qui choisit la version « retour » du
    // paywall, d'où qu'on l'ouvre.
    hasSubscribedBefore: subscriptions.length > 0,
  };
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Un abonnement App Store **qui va se renouveler**, et plus aucun voyage en
 * cours. Un voyage sans date de fin compte comme en cours : on ne pousse pas
 * à résilier quelqu'un qui n'a pas dit quand il rentrait.
 */
function outlivesEveryTrip(
  subscriptions: Subscription[],
  trips: { endDate: Date | null }[],
): boolean {
  const renews = subscriptions.some(
    (entry) => entry.provider === "storekit" && entry.status === "active" && entry.autoRenews !== false,
  );
  if (!renews) return false;

  // `endDate` est le minuit local du dernier jour : le voyage court encore
  // tout ce jour-là, d'où le jour ajouté.
  const now = Date.now();
  return !trips.some((trip) => trip.endDate === null || trip.endDate.getTime() + DAY_MS >= now);
}

/**
 * Le jour où la période payée du dernier abonnement s'est achevée, quand c'est
 * **récent**.
 *
 * `null` le reste du temps, et c'est tout l'intérêt : ce champ sert à ouvrir une
 * alerte, et une alerte annonce une nouvelle. Quelqu'un qui n'a pas ouvert l'app
 * depuis trois mois n'a pas besoin d'apprendre en sursaut qu'un abonnement s'est
 * arrêté au printemps — il le sait. L'app se souvient par ailleurs de l'avoir
 * montrée, donc ce champ ne fait que **cesser de proposer** au bout du délai.
 *
 * On lit `renewsAt` — la fin de la période réglée — et non `cancelledAt` : c'est
 * la date jusqu'à laquelle l'accès a duré, pas celle du geste de résiliation.
 * Un abonnement résilié le 3 avec un mois payé jusqu'au 31 s'arrête *pour de
 * bon* le 31, et c'est ce jour-là qui s'annonce.
 */
const RECENTLY_ENDED_DAYS = 14;

function justEndedSubscription(subscriptions: Subscription[]): Date | null {
  // Un abonnement encore vivant n'a rien à annoncer, quoi qu'en disent les
  // lignes plus anciennes de l'historique.
  if (subscriptions.some((entry) => entry.status === "active" || entry.status === "trialing")) {
    return null;
  }

  const now = Date.now();
  const floor = now - RECENTLY_ENDED_DAYS * 24 * 60 * 60 * 1000;

  const ended = subscriptions
    .filter((entry) => entry.status === "cancelled" || entry.status === "expired")
    .map((entry) => entry.renewsAt)
    .filter((date): date is Date => date !== null && date.getTime() <= now && date.getTime() >= floor)
    .sort((a, b) => b.getTime() - a.getTime());

  return ended[0] ?? null;
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
    validatedAt: iso(step.validatedAt),
  };
}

// ---------------------------------------------------------------------------
// Profil
// ---------------------------------------------------------------------------

type AccountForProfile = Account & {
  cards?: PaymentCard[];
  connectors?: AccountConnector[];
  subscriptions?: (Subscription & {
    memo?: { title: string; destinationCity: string | null } | null;
  })[];
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
    .filter((trip) => effectiveStage(trip) === "ongoing")
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

/**
 * L'adresse du profil, telle que `PostalAddress` la lit.
 *
 * `country` est le **code** ISO — la forme que la commande exige et que l'app
 * envoie depuis le 18/09/2026 — et `countryName` se **dérive** de la liste de
 * l'imprimeur : rien n'est stocké, c'est la ligne du profil qui l'affiche.
 * `addressCountry` est une colonne de texte libre et ancienne : « France »,
 * « FRANCE », parfois déjà « FR ». Ce qui s'y reconnaît devient un code ; ce
 * qui ne s'y reconnaît pas est rendu tel quel, pour les deux champs — l'écran
 * montre alors ce que la personne avait écrit, et le menu l'invite à choisir
 * un pays livrable. Inventer « FR » à sa place serait une adresse qui ment.
 */
function serializePostalAddress(account: Account) {
  const country = findShippingCountry(account.addressCountry);
  const raw = account.addressCountry?.trim() ?? "";

  return {
    street: account.addressLine1 ?? "",
    postalCode: account.addressPostalCode ?? "",
    city: account.addressCity ?? "",
    country: country?.code ?? raw,
    countryName: country?.name ?? raw,
  };
}

export function serializeProfile(
  account: AccountForProfile,
  orders: OrderForTracking[],
  trips: TripForProfileStats[] = [],
  now: Date = new Date(),
) {
  const fullName =
    [account.firstName, account.lastName]
      .filter((part): part is string => Boolean(part?.trim()))
      .join(" ") ||
    account.email ||
    "Voyageur";

  // L'abonnement en cours s'il y en a un, le plus récent sinon : c'est lui qui
  // porte le prix affiché, et un ancien abonné doit revoir le sien.
  const subscriptions = account.subscriptions ?? [];
  // `past_due` compris : pendant le délai de grâce, Apple garde l'accès ouvert
  // et retente le prélèvement — la feuille ne dit pas « résilié » à un abonné
  // dont la carte a seulement expiré.
  const active = subscriptions.find(
    (entry) => entry.status === "active" || entry.status === "trialing" || entry.status === "past_due",
  );
  const subscription = active ?? subscriptions[0];
  const isSubscribed = active !== undefined;
  // L'abonnement qui ouvre l'illimité aujourd'hui — vivant, ou résilié avec
  // un mois encore payé. C'est **lui seul** qui porte un prix à afficher :
  // un ancien abonné de la semaine revoit l'offre du mois, pas l'ancien tarif.
  const granting = subscriptions.find((entry) => grantsUnlimitedAccess(entry, now));
  const priceCents = granting?.priceCents ?? SUBSCRIPTION_MONTHLY_CENTS;
  const interval = granting?.interval === "week" ? "week" : "month";
  const defaultCard = account.cards?.find((card) => card.isDefault);

  return {
    fullName,
    email: account.email,
    // Décide d'une chose et d'une seule côté app : l'adresse ne se corrige pas.
    // Elle appartient au compte Apple ou Google.
    signInProvider: account.identities?.[0]?.provider ?? null,
    // Le compte a un mot de passe à lui : c'est ce qui fait exister la ligne
    // « Mot de passe » du profil (Hugo, 29/09/2026). `signInProvider` ne
    // suffisait pas — un compte entré par e-mail puis rattaché à Apple a les
    // deux.
    hasPassword: account.passwordHash !== null,
    phoneNumber: account.phoneNumber,
    // Le jour, `AAAA-MM-JJ` — pas un instant, qui se relirait dans le fuseau de
    // l'appareil et pourrait reculer d'un jour.
    birthDate: account.birthDate ? account.birthDate.toISOString().slice(0, 10) : null,
    // Ce que la personne a dit, sinon ce que son prénom laisse deviner : c'est
    // ce que la ligne « Genre » du profil affiche, et ce sur quoi la feuille
    // d'abonnement accorde « Abonné(e) » (T76).
    gender: effectiveGender(account.gender, account.firstName),
    avatarUrl: avatarUrlOf(account),
    address: serializePostalAddress(account),
    // La liste de l'imprimeur, avec le profil : la feuille « Adresse postale »
    // y choisit le pays, et un second appel ferait attendre un menu.
    shippingCountries: SHIPPING_COUNTRIES,
    wantsNewsletter: account.wantsNewsletter,
    // **Gelé à zéro** (06/10/2026) : la cagnotte est retirée du produit. Les
    // builds installés décodent ce champ comme obligatoire ; à retirer quand
    // plus aucun ne le lit.
    walletBalance: 0,
    cards: (account.cards ?? []).map(serializeCard),
    selectedCardId: defaultCard?.id ?? account.cards?.[0]?.id ?? null,
    connectors: serializeConnectors(account.connectors ?? []),
    subscription: {
      // **Le tarif du catalogue quand rien n'est en cours.** Un compte sans
      // abonnement n'a pas un abonnement à zéro euro : il n'en a pas. Rendre 0
      // faisait écrire « 0,00 € » à la feuille d'offre et au paywall — voir
      // `subscriptionCatalog.ts`. Le paywall lit d'abord le prix de StoreKit ;
      // celui-ci est son repli.
      price: euros(priceCents),
      interval,
      // **Le même prix, sous l'ancien nom** : les apps installées décodent
      // `weeklyPrice` comme obligatoire. Elles écriront « /semaine » derrière
      // 4,99 € jusqu'à leur mise à jour — mieux qu'un profil qui ne s'ouvre
      // plus (Hugo, 03/10/2026).
      weeklyPrice: euros(priceCents),
      isActive: isSubscribed,
      // Raconte-t-il sans limite aujourd'hui ? Plus large qu'`isActive` : un
      // abonnement résilié reste illimité jusqu'au bout du mois payé, et un
      // prélèvement en retard aussi, le temps qu'Apple tranche.
      isUnlimited: granting !== undefined,
      cancelledAt: iso(subscription?.cancelledAt ?? null),
      // **Jusqu'où la période payée porte.** `renewsAt` est la fin de la
      // période déjà réglée : c'est elle qui donne son sursis à une résiliation
      // — l'app comme le serveur laissent raconter sans limite jusque-là
      // (Hugo, 16/09/2026). Nul quand rien n'a été payé.
      paidThrough: iso(subscription?.renewsAt ?? null),
      // Le voyage qu'il finance (T71) : la ville pour « ton carnet de Rome »,
      // le titre pour le reste. Nuls tant que rien n'est rattaché.
      tripTitle: subscription?.memo?.title ?? null,
      tripDestination: subscription?.memo?.destinationCity ?? null,
      // **Déduit, pas stocké** : un abonnement terminé dans l'historique du
      // compte, et aucun en cours. C'est ce qui fait voir le paywall de retour
      // — deux écrans au lieu de trois — à quelqu'un qui repart en voyage.
      // **Apple tient l'abonnement** : la résiliation passe par la feuille
      // d'abonnements d'iOS, pas par une route d'ici — voir
      // `POST /v1/profile/subscription/cancel`.
      managedByAppStore: subscription?.provider === "storekit",
      hasEndedBefore:
        !isSubscribed &&
        (account.subscriptions ?? []).some(
          (entry) => entry.status === "cancelled" || entry.status === "expired",
        ),
    },
    orders: orders.map(serializeOrderTracking),
    ...serializeProfileStats(trips),
  };
}

// ---------------------------------------------------------------------------
// Paramètres du voyage, aperçu du carnet
// ---------------------------------------------------------------------------
//
// Même règle que ci-dessus : la forme suit `TripSettings`, `Wallet` (gelé) et
// `BookPreview` de `MemoBookCore` au champ près.

type MemoForSettings = Memo & {
  members?: (MemoMember & { account?: Account | null })[];
  renders?: { id: string; pdfUrl?: string | null }[];
  owner?: Account | null;
};

/**
 * Ce que l'écran des réglages d'un voyage montre, **vu par quelqu'un** :
 * `viewerAccountId` décide de ce que seul le propriétaire peut faire.
 */
export function serializeTripSettings(
  memo: MemoForSettings,
  dailyCredit: DailyCredit,
  viewerAccountId: string,
) {
  const isOwner = memo.ownerAccountId === viewerAccountId;
  return {
    tripId: memo.id,
    name: memo.title,
    // **Gelé à zéro** (06/10/2026) : la cagnotte est retirée du produit. Les
    // builds installés décodent ce champ comme obligatoire ; à retirer quand
    // plus aucun ne le lit.
    walletBalance: 0,
    // **Le crédit du jour du voyage**, vu par celui qui lit (Hugo,
    // 03/10/2026) — la ligne « Crédit du jour » des réglages. Il remplace la
    // clé `memory` des limites de souvenirs, qui disparaît : une app installée
    // la lisait en optionnel, la ligne s'efface proprement.
    dailyCredit: serializeDailyCredit(dailyCredit),
    startDate: iso(memo.startDate),
    endDate: iso(memo.endDate),
    narrationPace: memo.narrationPace,
    wantsNotifications: memo.notificationsEnabled,
    notifications: {
      writingReminder: memo.notifyWritingReminder,
      newStory: memo.notifyNewStory,
      weeklyDigest: memo.notifyWeeklyDigest,
      tripEndReminder: memo.notifyTripEnd,
    },
    // Le propriétaire **d'abord**, puis les invités dans l'ordre où ils ont été
    // conviés. C'est l'ordre de la feuille, et il n'est pas décoratif : la
    // première ligne dit qui tient le voyage.
    companions: [
      ...(memo.owner ? [serializeOwner(memo.owner)] : []),
      ...(memo.members ?? []).map(serializeCompanion),
    ],
    // Le code qu'on colle dans un message pour faire entrer quelqu'un.
    accessCode: memo.accessCode,
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
    // Le PDF du dernier rendu prêt — celui que `settingsInclude` va déjà
    // chercher. C'est lui que les feuilles de personnalisation feuillettent
    // au-dessus d'elles ; nul tant qu'aucun carnet n'a été composé.
    bookPdfUrl: memo.renders?.[0]?.pdfUrl ?? null,
    isPrintable: memo.isPrintable,
    customisation: serializeBookCustomisation(memo),
    // « Supprimer la conversation » n'appartient qu'au propriétaire, comme
    // supprimer le voyage (`docs/conversation.md` § 7). L'app pâlit le lien et
    // explique ; le serveur refuse quand même (`DELETE /v1/trips/:id/chat`).
    canClearConversation: isOwner,
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
  // Les pointillés sont `rulesEnabled`, les lignes sous le texte ; les cadres,
  // les zones libres pour écrire à la main. Les deux étaient croisés : depuis
  // le verrou des pointillés, un carnet *Manuscrit* — sans pointillés —
  // s'annonçait « Pointillés, … » sur la ligne « Style du carnet ».
  const active = [
    memo.rulesEnabled ? "Pointillés" : null,
    memo.freeZonesEnabled ? "cadres" : null,
    memo.funFactsEnabled ? "anecdotes" : null,
    memo.quizEnabled ? "quiz" : null,
    memo.crosswordEnabled ? "mots croisés" : null,
  ].filter((label): label is string => label !== null);

  if (active.length === 0) return "Aucun décor";
  return active.length > 3 ? `${active.slice(0, 3).join(", ")}, etc.` : active.join(", ");
}

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
 * **La cagnotte gelée** (06/10/2026 — « on supprime la cagnotte ») : un solde
 * à zéro, sans historique, pour le seul champ `wallet` d'`order-context` que
 * les builds installés décodent encore comme obligatoire. Plus aucune route
 * ne sert de cagnotte ; à retirer quand plus aucun build ne le lit.
 */
export function frozenWallet(
  trip: Pick<Memo, "id" | "title" | "destinationCity" | "targetPageCount" | "pageCount">,
) {
  return serializeWallet(0, [], trip);
}

/**
 * La forme d'une cagnotte, telle que ``Wallet`` la décode côté Swift. Ne sert
 * plus qu'à `frozenWallet`.
 */
function serializeWallet(
  balanceCents: number,
  entries: WalletEntryRow[],
  trip: Pick<Memo, "id" | "title" | "destinationCity" | "targetPageCount" | "pageCount"> | null,
) {
  return {
    // Le carnet que cette cagnotte finance — celui qu'on a demandé, ou celui
    // que la route a choisi quand on arrive du profil. C'est lui que « Prévisualiser
    // mon carnet » ouvre et que « Partager » met dans le message.
    tripId: trip?.id ?? null,
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
  return {
    pageCount: pages,
    cost: euros(unitPriceCents(pages)),
    // Plus de dates ni de semaines ici : elles servaient la feuille
    // « Estimation » du paywall, qui déduisait les abonnements du carnet. Il
    // n'y a plus rien à déduire (Hugo, 03/10/2026) ; les trois champs sont
    // optionnels côté Swift.
  };
}

type MemoForPreview = Memo & {
  renders?: { id: string; status: string; pdfUrl?: string | null }[];
  entries?: EntryTextRow[];
};

/** L'aperçu du carnet : le PDF composé, et de quoi le partager. */
export function serializeBookPreview(
  memo: MemoForPreview,
  lastReadyPdfUrl: string | null,
  publicBaseUrl: string,
) {
  const render = memo.renders?.[0];
  const excerpt = serializeExcerpt(memo.entries ?? []);

  return {
    memoId: memo.id,
    // Le titre du récit s'il s'en est donné un, celui du voyage sinon.
    title: memo.bookTitle?.trim() || memo.title,
    // Le statut vient du dernier rendu, même en cours — c'est lui qui annonce
    // une régénération. Le PDF, lui, vient du dernier rendu **prêt** : sans
    // ça, une régénération en fond ferait disparaître le carnet déjà affiché
    // (`renders.take: 1` ne voit que le rendu en cours, `pdfUrl: null`) le
    // temps qu'elle aboutisse.
    status: serializeRenderStatus(render?.status),
    pdfUrl: lastReadyPdfUrl,
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
