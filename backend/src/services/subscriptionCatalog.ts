/**
 * Le catalogue de l'abonnement : ce que ça coûte, écrit **une seule fois**.
 *
 * **Il existe parce qu'un prix absent n'est pas un prix nul.** `GET /v1/profile`
 * rendait `weeklyPrice: 0` à qui n'est pas encore abonné — il n'y a pas de ligne
 * `subscriptions` à lire tant qu'on n'a rien souscrit — et l'app affichait donc
 * « 0,00 €/semaine » sur la feuille d'offre, sur le paywall, et « 3 x 0,00 € »
 * sur la feuille d'estimation. Le prix de l'offre ne dépend pas de ce que la
 * personne a déjà acheté : c'est un tarif, il vit dans un catalogue.
 *
 * ⚠️ **Ce catalogue ne remplace pas le fournisseur, il le double.** L'abonnement
 * s'achète par StoreKit — Apple impose l'achat intégré pour un service
 * numérique, voir `PAYMENT_KIND` dans `billing.ts` —, et c'est App Store Connect
 * qui aura le dernier mot sur le montant affiché dans l'app. Les références
 * Stripe sont là pour le jour où l'offre se vend aussi hors de l'app (le web),
 * et pour que le back-end sache de quel prix il parle ; le sandbox Stripe du
 * projet porte déjà le prix hebdomadaire sous la clé
 * `memobook_subscription_weekly`.
 */

/** Le prix de l'abonnement hebdomadaire, en centimes. */
export const SUBSCRIPTION_WEEKLY_CENTS = 199;

/**
 * Le supplément mensuel qui relève les limites de souvenirs, en centimes.
 *
 * Mensuel et non hebdomadaire, contrairement à l'abonnement : ce n'est pas le
 * voyage qu'il suit mais l'appétit de celui qui raconte, et une limite se
 * compte par mois — voir `memoryAllowance.ts`.
 */
export const MEMORY_UPGRADE_MONTHLY_CENTS = 399;

/** La devise du catalogue. Une seule pour l'instant. */
export const CATALOG_CURRENCY = "EUR";

/**
 * Les clés de recherche Stripe, stables d'un environnement à l'autre.
 *
 * Une `lookup_key` et non un identifiant de prix : celui-ci change entre le
 * sandbox et la production, celle-là non. C'est ce qui permet de poser la même
 * valeur dans les deux comptes sans variable d'environnement de plus.
 */
export const STRIPE_LOOKUP_KEYS = {
  weeklySubscription: "memobook_subscription_weekly",
  memoryUpgrade: "memobook_memory_upgrade_monthly",
} as const;
