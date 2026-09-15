/**
 * Les pays où l'imprimeur livre.
 *
 * **Servi à l'app plutôt que codé en dur des deux côtés** : la liste est une
 * contrainte de l'imprimeur, elle changera sans qu'on livre une version d'iOS.
 * Le champ « Pays » de l'étape 2 est donc un choix dans cette liste, et pas un
 * texte libre — une adresse dont le pays n'est pas livrable est une commande
 * qu'on accepte pour la refuser plus tard.
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

export const SHIPPING_COUNTRY_CODES = SHIPPING_COUNTRIES.map((country) => country.code);

/**
 * Ramène ce qu'on a sous la main à un code livrable.
 *
 * L'adresse du profil est un texte libre et ancien — « France », « FRANCE »,
 * parfois déjà « FR ». Elle sert d'**amorce** au formulaire, donc elle doit
 * retomber sur un code sans jamais faire échouer l'ouverture de l'écran : à
 * défaut de reconnaître, on propose la France et l'utilisateur corrige.
 */
export function toShippingCountryCode(raw: string | null | undefined): string {
  const value = raw?.trim();
  if (!value) return "FR";

  const upper = value.toUpperCase();
  const byCode = SHIPPING_COUNTRIES.find((country) => country.code === upper);
  if (byCode) return byCode.code;

  const byName = SHIPPING_COUNTRIES.find(
    (country) => country.name.toLocaleUpperCase("fr-FR") === upper,
  );
  return byName?.code ?? "FR";
}
