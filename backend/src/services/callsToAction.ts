/**
 * **Les appels à l'action d'une bulle de MEMO** (03/10/2026) — le bouton qui
 * se pose sous le texte d'une bulle, séparé par un filet, avec « Ignorer »
 * en dessous (maquettes Figma `3653:17090` et `3653:17213`).
 *
 * Un message de MEMO en porte **un au plus**, rangé dans
 * `chat_messages.payload.callToAction = { id }`. Le sérialiseur du fil le
 * résout ici, au moment de la lecture, et pour **celui qui lit** : un abonné
 * ne voit jamais d'offre d'abonnement.
 *
 * **Le modèle propose, le code dispose** — la même règle que les puces. L'IA
 * de conversation choisit un identifiant parmi ceux que le tour lui permet
 * (`allowedForModel`) ; elle n'écrit ni le libellé, ni l'action, ni une
 * adresse. Une transcription ou un texte du voyageur entre dans son prompt :
 * lui laisser écrire un bouton serait ouvrir une porte d'injection.
 *
 * Ajouter un appel à l'action, c'est ajouter une ligne ici et un cas à
 * `ChatCallToAction.Kind` dans l'app. Une app plus ancienne qui reçoit une
 * action qu'elle ne connaît pas n'affiche pas le bouton — le texte de la bulle
 * doit donc toujours se suffire à lui-même.
 */

/** Ce que l'app fait quand on touche le bouton. */
export const CALL_TO_ACTION_KINDS = [
  /** Ouvrir le paywall. */
  "subscribe",
  /** Ouvrir les réglages du voyage. */
  "open_trip_settings",
  /** Ouvrir l'aperçu du carnet. */
  "open_preview",
  /** Ouvrir le sélecteur de photos. */
  "import_photos",
  /** Ouvrir la page de MemoBook dans les Réglages d'iOS (accès aux photos). */
  "open_photo_settings",
] as const;

export type CallToActionKind = (typeof CALL_TO_ACTION_KINDS)[number];

type CallToActionDefinition = {
  kind: CallToActionKind;
  /** Le libellé du bouton, au caractère près. */
  label: string;
  /** L'en-tête manuscrit de la carte, précédé d'une étoile dans l'app. */
  eyebrow: string;
  /** « Ignorer » sous le bouton. */
  dismissible: boolean;
  /** L'IA de conversation peut-elle le choisir ? Sinon, seul le code le pose. */
  allowedForModel: boolean;
};

export const CALLS_TO_ACTION = {
  /**
   * Posé par le serveur sous la bulle « reviens demain », quand le crédit du
   * jour du voyage est épuisé (`services/dailyCredit.ts`).
   */
  daily_credit_subscribe: {
    kind: "subscribe",
    label: "Raconter sans limite",
    eyebrow: "Crédit du jour épuisé",
    dismissible: true,
    allowedForModel: false,
  },
  /**
   * Quand le voyageur demande ce que coûte l'abonnement ou ce qu'il ouvre —
   * jamais de lui-même.
   */
  subscribe: {
    kind: "subscribe",
    label: "Découvrir l’abonnement",
    eyebrow: "Raconter sans limite",
    dismissible: true,
    allowedForModel: true,
  },
  open_trip_settings: {
    kind: "open_trip_settings",
    label: "Ouvrir les réglages du voyage",
    eyebrow: "Réglages du voyage",
    dismissible: true,
    allowedForModel: true,
  },
  open_preview: {
    kind: "open_preview",
    label: "Voir l’aperçu du carnet",
    eyebrow: "Aperçu du carnet",
    dismissible: true,
    allowedForModel: true,
  },
  import_photos: {
    kind: "import_photos",
    label: "Ajouter des photos",
    eyebrow: "Suggestions",
    dismissible: true,
    allowedForModel: true,
  },
  /**
   * L'accès aux photos est limité : seule l'app le sait, c'est donc elle qui
   * le demande au serveur (ou qui pose la bulle elle-même). Jamais le modèle.
   */
  open_photo_settings: {
    kind: "open_photo_settings",
    label: "Modifier l’autorisation",
    eyebrow: "Accès aux photos limité",
    dismissible: true,
    allowedForModel: false,
  },
} as const satisfies Record<string, CallToActionDefinition>;

export type CallToActionId = keyof typeof CALLS_TO_ACTION;

export const CALL_TO_ACTION_IDS = Object.keys(CALLS_TO_ACTION) as CallToActionId[];

/** Ceux que l'IA de conversation a le droit de proposer. */
export const MODEL_CALL_TO_ACTION_IDS = CALL_TO_ACTION_IDS.filter(
  (id) => CALLS_TO_ACTION[id].allowedForModel,
);

/** Ce que l'app reçoit sous `message.callToAction`. */
export type SerializedCallToAction = {
  id: CallToActionId;
  kind: CallToActionKind;
  label: string;
  eyebrow: string;
  dismissible: boolean;
};

export function isCallToActionId(value: unknown): value is CallToActionId {
  return typeof value === "string" && Object.hasOwn(CALLS_TO_ACTION, value);
}

/**
 * Résout l'appel à l'action rangé dans le payload d'une bulle, **pour celui
 * qui lit**. Rend `null` pour un identifiant inconnu — un payload écrit par
 * une version plus récente ne doit pas faire tomber le fil — et pour une offre
 * d'abonnement lue par quelqu'un qui raconte déjà sans limite.
 */
export function resolveCallToAction(
  stored: unknown,
  viewer: { isUnlimited: boolean },
): SerializedCallToAction | null {
  if (!stored || typeof stored !== "object") return null;
  const id = (stored as { id?: unknown }).id;
  if (!isCallToActionId(id)) return null;

  const definition = CALLS_TO_ACTION[id];
  if (definition.kind === "subscribe" && viewer.isUnlimited) return null;

  return {
    id,
    kind: definition.kind,
    label: definition.label,
    eyebrow: definition.eyebrow,
    dismissible: definition.dismissible,
  };
}
