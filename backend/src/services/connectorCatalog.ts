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
 * `logoAssetName` nomme un `imageset` de `MemoBookAssets.xcassets` — ce sont
 * des marques tierces, elles ne se teintent pas et ne se remplacent pas par une
 * icône MemoBook. **Le nom doit exister côté app** : rien ici ne le vérifie, et
 * une clé sans fichier en face rend une pastille à initiale. Le jour où les
 * logos seront servis en URL, ce champ disparaîtra au profit de
 * `account_connectors.logoUrl`.
 */
export interface ConnectorDefinition {
  key: string;
  name: string;
  promise: string;
  logoAssetName: string;
}

/**
 * Les six de la maquette, **et les six qui ont un logo**.
 *
 * Les deux vont ensemble : `logoAssetName` doit nommer un `imageset` réellement
 * embarqué dans `MemoBookAssets.xcassets`, sinon l'app affiche une pastille à
 * initiale à la place d'une marque. Le catalogue a longtemps servi six autres
 * services — Google Photos, Photos, Google Maps, Tricount, Spotify — avec des
 * noms d'asset qui n'existaient nulle part : la feuille arrivait alors sans un
 * seul logo.
 *
 * Les cinq écartés restent les prochains candidats. Il leur manque un export :
 * ajouter la clé ici sans le fichier en face rejouerait exactement le même bug.
 */
export const CONNECTOR_CATALOG: readonly ConnectorDefinition[] = [
  {
    key: "strava",
    name: "Strava",
    promise:
      "MemoBook pourra déduire tes étapes et t'aider à raconter des souvenirs à partir de tes runs",
    logoAssetName: "ConnectorStrava",
  },
  {
    key: "alltrails",
    name: "All Trails",
    promise:
      "MemoBook pourra récupérer tes sentiers parcourus et t'aider à raconter des souvenirs de tes randonnées",
    logoAssetName: "ConnectorAllTrails",
  },
  {
    key: "garmin",
    name: "Garmin",
    promise:
      "MemoBook pourra récupérer tes activités enregistrées et t'aider à situer tes étapes sur le trajet",
    logoAssetName: "ConnectorGarmin",
  },
  {
    key: "polarsteps",
    name: "PolarSteps",
    promise: "MemoBook pourra récupérer tes récits PolarSteps et t'aider à compléter ton carnet",
    logoAssetName: "ConnectorPolarSteps",
  },
  {
    key: "airbnb",
    name: "Airbnb",
    promise:
      "MemoBook pourra déduire tes étapes et t'aider à raconter des souvenirs à partir de tes réservations",
    logoAssetName: "ConnectorAirbnb",
  },
  {
    key: "booking",
    name: "Booking",
    promise:
      "MemoBook pourra déduire tes étapes et t'aider à raconter des souvenirs à partir de tes réservations",
    logoAssetName: "ConnectorBooking",
  },
] as const;

export function connectorByKey(key: string): ConnectorDefinition | undefined {
  return CONNECTOR_CATALOG.find((connector) => connector.key === key);
}
