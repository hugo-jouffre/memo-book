/**
 * Les services tiers que MemoBook sait brancher.
 *
 * Le catalogue vit **côté serveur** et non dans l'app : en ajouter un, ou
 * réécrire ce qu'il promet, ne doit pas demander une version de l'App Store.
 * `account_connectors` ne stocke que la clé et l'état — le libellé vient d'ici.
 *
 * `promise` est le texte de consentement, pas une accroche marketing : c'est
 * ce que la personne lit avant d'ouvrir son compte à quelqu'un d'autre. Une
 * phrase, au présent, qui dit ce qu'on va chercher et rien de plus.
 *
 * `logoAssetName` désigne un visuel embarqué dans l'app — ce sont des marques
 * tierces, elles ne se teintent pas et ne se remplacent pas par une icône
 * MemoBook. Le jour où les logos seront servis en URL, ce champ disparaîtra au
 * profit de `account_connectors.logoUrl`.
 */
export interface ConnectorDefinition {
  key: string;
  name: string;
  promise: string;
  logoAssetName: string;
}

export const CONNECTOR_CATALOG: readonly ConnectorDefinition[] = [
  {
    key: "google-photos",
    name: "Google Photos",
    promise: "Retrouve les photos prises pendant les dates du voyage.",
    logoAssetName: "connector-google-photos",
  },
  {
    key: "apple-photos",
    name: "Photos",
    promise: "Retrouve les photos prises pendant les dates du voyage.",
    logoAssetName: "connector-apple-photos",
  },
  {
    key: "google-maps",
    name: "Google Maps",
    promise: "Relit l'historique des lieux pour situer les étapes.",
    logoAssetName: "connector-google-maps",
  },
  {
    key: "tricount",
    name: "Tricount",
    promise: "Importe les dépenses pour dater et situer les étapes.",
    logoAssetName: "connector-tricount",
  },
  {
    key: "strava",
    name: "Strava",
    promise: "Récupère les trajets pour calculer les distances parcourues.",
    logoAssetName: "connector-strava",
  },
  {
    key: "spotify",
    name: "Spotify",
    promise: "Note ce que tu écoutais, pour l'ambiance du carnet.",
    logoAssetName: "connector-spotify",
  },
] as const;

export function connectorByKey(key: string): ConnectorDefinition | undefined {
  return CONNECTOR_CATALOG.find((connector) => connector.key === key);
}
