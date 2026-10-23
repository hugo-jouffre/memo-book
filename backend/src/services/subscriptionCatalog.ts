/**
 * Le catalogue de l'abonnement : ce que ça coûte, écrit **une seule fois**.
 *
 * **Il existe parce qu'un prix absent n'est pas un prix nul.** `GET /v1/profile`
 * rendait un prix à 0 à qui n'est pas encore abonné — il n'y a pas de ligne
 * `subscriptions` à lire tant qu'on n'a rien souscrit — et l'app affichait donc
 * « 0,00 € » sur la feuille d'offre et sur le paywall. Le prix de l'offre ne
 * dépend pas de ce que la personne a déjà acheté : c'est un tarif, il vit dans
 * un catalogue.
 *
 * **L'offre, depuis le 03/10/2026 (Hugo)** : un abonnement **mensuel à 4,99 €**,
 * qui rend le récit illimité pour l'abonné. Tout le monde raconte gratuitement
 * 5 minutes par jour et par voyage (`dailyCredit.ts`) ; il n'y a plus ni étapes
 * offertes, ni limites de souvenirs à étendre, ni abonnement hebdomadaire, ni
 * abonnements déduits du prix du carnet. L'ancien modèle est sur la branche
 * `icebox/abonnement-hebdomadaire`.
 *
 * ⚠️ **Ce catalogue ne remplace pas le fournisseur, il le double.** L'abonnement
 * s'achète par StoreKit — Apple impose l'achat intégré pour un service
 * numérique, voir `PAYMENT_KIND` dans `billing.ts` —, et c'est App Store Connect
 * qui a le dernier mot sur le montant affiché dans l'app (`displayPrice`). Le
 * prix d'ici sert de repli au profil, et dit au back-end de quel prix il parle.
 */

/** Le prix de l'abonnement mensuel, en centimes. */
export const SUBSCRIPTION_MONTHLY_CENTS = 499;

/** La devise du catalogue. Une seule pour l'instant. */
export const CATALOG_CURRENCY = "EUR";

/**
 * Les clés de recherche Stripe, stables d'un environnement à l'autre.
 *
 * Une `lookup_key` et non un identifiant de prix : celui-ci change entre le
 * sandbox et la production, celle-là non. **Stripe n'encaisse pas
 * l'abonnement** — c'est Apple — : la clé est là pour le jour où l'offre se
 * vendra aussi hors de l'app (le web), et pour que le prix Stripe porte le
 * même nom partout.
 */
export const STRIPE_LOOKUP_KEYS = {
  monthlySubscription: "memobook_subscription_monthly",
} as const;

/**
 * Les produits App Store — **ceux qui encaissent vraiment**, dans l'app.
 *
 * L'identifiant est posé dans *App Store Connect ▸ Abonnements* (groupe
 * « MemoBook ») et ne se change plus jamais : Apple ne le laisse ni modifier
 * ni réutiliser, même après suppression. L'app porte la même valeur
 * (`StoreKitCatalog`) et `MemoBook.storekit` aussi ; les trois doivent rester
 * identiques.
 *
 * - `monthlySubscription` : **le seul produit vendu**.
 * - `legacyWeeklySubscription` : l'ancien abonnement hebdomadaire. Plus vendu
 *   nulle part dans l'app, mais **toujours accepté** : un abonné de la semaine
 *   reste illimité jusqu'à l'expiration de ce qu'il a payé, et ses
 *   renouvellements, expirations et remboursements doivent continuer d'écrire
 *   sa ligne — l'ignorer le laisserait illimité à vie.
 */
export const APP_STORE_PRODUCT_IDS = {
  monthlySubscription: "com.memobook.app.subscription.monthly",
  legacyWeeklySubscription: "com.memobook.app.subscription.weekly",
} as const;

/** Ce que chaque produit accepté vaut, et à quel rythme il se renouvelle. */
export const APP_STORE_PRODUCTS: Readonly<
  Record<string, { interval: "month" | "week"; priceCents: number }>
> = {
  [APP_STORE_PRODUCT_IDS.monthlySubscription]: { interval: "month", priceCents: SUBSCRIPTION_MONTHLY_CENTS },
  // Le prix de l'ancienne offre, en repli seulement : une transaction Apple
  // porte son propre prix, et c'est lui qu'on écrit.
  [APP_STORE_PRODUCT_IDS.legacyWeeklySubscription]: { interval: "week", priceCents: 199 },
};

/** Ce produit ouvre-t-il l'abonnement ? Un autre est refusé, jamais deviné. */
export function isAcceptedAppStoreProduct(productId: string): boolean {
  return Object.hasOwn(APP_STORE_PRODUCTS, productId);
}

/**
 * Les produits Google Play — l'app Android (lot B4, 22/10/2026).
 *
 * **Le même identifiant que l'App Store**, posé dans *Play Console ▸
 * Monétiser ▸ Abonnements* avec un plan de base mensuel à 4,99 €. L'app porte
 * la même valeur (`PlayCatalog`, `android/payments`) ; les deux doivent rester
 * identiques. Google ne laisse pas non plus réutiliser un identifiant supprimé.
 *
 * Pas d'hebdomadaire ici : il n'a jamais été vendu sur Android.
 */
export const GOOGLE_PLAY_PRODUCT_IDS = {
  monthlySubscription: APP_STORE_PRODUCT_IDS.monthlySubscription,
} as const;

/** Ce que chaque produit Play accepté vaut, et à quel rythme il se renouvelle. */
export const GOOGLE_PLAY_PRODUCTS: Readonly<
  Record<string, { interval: "month" | "week"; priceCents: number }>
> = {
  [GOOGLE_PLAY_PRODUCT_IDS.monthlySubscription]: { interval: "month", priceCents: SUBSCRIPTION_MONTHLY_CENTS },
};

/** Ce produit Play ouvre-t-il l'abonnement ? */
export function isAcceptedGooglePlayProduct(productId: string): boolean {
  return Object.hasOwn(GOOGLE_PLAY_PRODUCTS, productId);
}

/** Le paquet de l'app Android — celui de la fiche Play et de ses abonnements. */
export const GOOGLE_PLAY_PACKAGE = "com.memobook.app";

/**
 * La page des abonnements d'Apple — sur un iPhone, elle ouvre Réglages ▸ ton
 * nom ▸ Abonnements. Un abonnement App Store ne se coupe que là : Apple ne
 * laisse aucune app résilier à la place de son client.
 */
export const APPLE_SUBSCRIPTIONS_URL = "https://apps.apple.com/account/subscriptions";

/**
 * La page des abonnements de Google Play pour ce produit — ce que l'app
 * Android ouvre pour résilier (`SubscriptionSheet.playSubscriptionsUrl`, la
 * même adresse), et le bouton de l'e-mail de fin de voyage. Comme chez Apple,
 * seul le store résilie.
 */
export function googlePlaySubscriptionsUrl(
  productId: string = GOOGLE_PLAY_PRODUCT_IDS.monthlySubscription,
  packageName: string = GOOGLE_PLAY_PACKAGE,
): string {
  return (
    "https://play.google.com/store/account/subscriptions" +
    `?sku=${encodeURIComponent(productId)}&package=${encodeURIComponent(packageName)}`
  );
}

/** Où se gère l'abonnement que tient ce store. */
export function storeManageUrl(store: "app_store" | "google_play", productId?: string | null): string {
  return store === "google_play" ? googlePlaySubscriptionsUrl(productId ?? undefined) : APPLE_SUBSCRIPTIONS_URL;
}
