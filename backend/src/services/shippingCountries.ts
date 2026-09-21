/**
 * Les pays où l'imprimeur livre.
 *
 * **Servi à l'app plutôt que codé en dur des deux côtés** : la liste est une
 * contrainte de l'imprimeur, elle changera sans qu'on livre une version d'iOS.
 * Le champ « Pays » de l'étape 2 est donc un choix dans cette liste, et pas un
 * texte libre — une adresse dont le pays n'est pas livrable est une commande
 * qu'on accepte pour la refuser plus tard. Depuis le 18/09/2026, le champ
 * « Pays » de l'adresse du profil est le même choix, dans la même liste : le
 * profil est l'amorce de la commande, il ne doit pas pouvoir dire un pays que
 * la commande refusera.
 *
 * Le code est l'ISO 3166-1 alpha-2, seule forme que la base garde et que
 * l'imprimeur lit. Le nom n'existe que pour l'écran.
 */
export const SHIPPING_COUNTRIES = [
  { code: "FR", name: "France" },
  { code: "BE", name: "Belgique" },
  { code: "CH", name: "Suisse" },
  { code: "LU", name: "Luxembourg" },
  { code: "DE", name: "Allemagne" },
  { code: "ES", name: "Espagne" },
  { code: "IT", name: "Italie" },
  { code: "PT", name: "Portugal" },
  { code: "NL", name: "Pays-Bas" },
  { code: "IE", name: "Irlande" },
  { code: "AT", name: "Autriche" },
  { code: "GB", name: "Royaume-Uni" },
  { code: "CA", name: "Canada" },
  { code: "US", name: "États-Unis" },
] as const;

export type ShippingCountry = (typeof SHIPPING_COUNTRIES)[number];

export const SHIPPING_COUNTRY_CODES = SHIPPING_COUNTRIES.map((country) => country.code);

/**
 * Le pays livrable que désigne ce texte, s'il y en a un.
 *
 * Reconnaît le code (« FR », « fr ») comme le nom (« France », « FRANCE ») :
 * `accounts.addressCountry` est une colonne de texte libre et ancienne, où les
 * deux formes cohabitent. `undefined` quand rien n'y correspond — c'est à
 * l'appelant de décider ce qu'il en fait, et les deux appelants ne décident
 * pas la même chose.
 */
export function findShippingCountry(raw: string | null | undefined): ShippingCountry | undefined {
  const value = raw?.trim();
  if (!value) return undefined;

  const upper = value.toLocaleUpperCase("fr-FR");
  return SHIPPING_COUNTRIES.find(
    (country) => country.code === upper || country.name.toLocaleUpperCase("fr-FR") === upper,
  );
}

/**
 * Ramène ce qu'on a sous la main à un code livrable, **pour amorcer une
 * commande**.
 *
 * L'adresse du profil sert d'amorce au formulaire de l'étape 2, donc elle doit
 * retomber sur un code sans jamais faire échouer l'ouverture de l'écran : à
 * défaut de reconnaître, on propose la France et l'utilisateur corrige.
 */
export function toShippingCountryCode(raw: string | null | undefined): string {
  return findShippingCountry(raw)?.code ?? "FR";
}
