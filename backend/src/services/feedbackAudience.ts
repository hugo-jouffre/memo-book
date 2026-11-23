import type { Prisma } from "@prisma/client";
import type { AppContext } from "../context.js";
import { hasUnlimitedAccess } from "./subscriptions.js";

/**
 * **À qui une campagne d'avis s'adresse** (T273, reste du 23/11/2026).
 *
 * La colonne `feedback_campaigns.audience` existait depuis le 07/09/2026 et
 * personne ne la lisait : le serveur **refusait** donc de servir une campagne
 * qui en portait une, parce qu'une modale servie à côté de sa cible est pire
 * qu'une modale qui ne paraît pas. Elle se lit maintenant.
 *
 * ## Quatre critères, et pas un de plus
 *
 * ```json
 * { "registeredForDays": 7, "hasOrdered": true, "isSubscriber": false, "minMemories": 5 }
 * ```
 *
 * Ils se cumulent : une campagne qui en porte deux ne paraît qu'à ceux qui
 * remplissent les deux. Chacun répond à une question qu'on s'est posée pour
 * de vrai — « ceux qui ont reçu leur carnet », « ceux qui viennent
 * d'arriver », « ceux qui racontent déjà ».
 *
 * ⚠️ **Un critère inconnu ferme la campagne**, comme avant : une audience
 * qu'on ne sait pas lire ne vaut pas une audience vide. C'est ce qui permet
 * d'en inventer un en base sans risquer qu'il soit ignoré en silence — la
 * campagne attendra la version qui le comprend, et le dira dans les journaux.
 *
 * ⚠️ **Une audience vide (`{}`) s'adresse à tout le monde.** C'est le même
 * sens que `null`, écrit autrement, et c'est volontairement permissif : la
 * ruse d'écrire `{}` pour « personne » ferait une campagne invisible qu'on
 * croirait posée.
 */
export interface FeedbackAudience {
  /** Le compte existe depuis au moins tant de jours. */
  registeredForDays?: number;
  /** Il a déjà commandé un carnet imprimé — brouillons exclus. */
  hasOrdered?: boolean;
  /** Il raconte sans limite, aujourd'hui. */
  isSubscriber?: boolean;
  /** Il a déjà écrit ou dicté au moins tant de souvenirs — photos exclues. */
  minMemories?: number;
}

const CRITERIA = ["registeredForDays", "hasOrdered", "isSubscriber", "minMemories"] as const;

/** Une commande qui n'est plus un brouillon : le carnet est parti à l'atelier. */
const ORDERED: Prisma.EnumPrintOrderStatusFilter = {
  in: ["submitted", "in_production", "shipped"],
};

/**
 * L'audience telle qu'elle est écrite, ou `null` si on ne sait pas la lire —
 * **et `null` ferme la campagne** côté appelant.
 *
 * Relue défensivement, comme `memos.coherenceSheet` : c'est du JSON écrit à la
 * main dans une console SQL, et une faute de frappe ne doit pas servir la
 * campagne à tout le monde.
 */
export function parseAudience(value: unknown): FeedbackAudience | null {
  if (value === null || value === undefined) return {};
  if (typeof value !== "object" || Array.isArray(value)) return null;

  const raw = value as Record<string, unknown>;
  const audience: FeedbackAudience = {};

  for (const [key, written] of Object.entries(raw)) {
    if (!(CRITERIA as readonly string[]).includes(key)) return null;
    switch (key) {
      case "registeredForDays":
      case "minMemories": {
        if (typeof written !== "number" || !Number.isInteger(written) || written < 0) return null;
        audience[key] = written;
        break;
      }
      case "hasOrdered":
      case "isSubscriber": {
        if (typeof written !== "boolean") return null;
        audience[key] = written;
        break;
      }
    }
  }

  return audience;
}

/**
 * Ce compte est-il dans l'audience ?
 *
 * Les critères se lisent **du moins cher au plus cher**, et le premier qui
 * échoue arrête la lecture : une campagne pour les abonnés de la première
 * heure ne compte pas les souvenirs de tous ceux qui ne sont pas abonnés.
 */
export async function matchesAudience(
  context: AppContext,
  audience: FeedbackAudience,
  accountId: string,
  now: Date,
): Promise<boolean> {
  const { prisma } = context;

  if (audience.registeredForDays !== undefined) {
    const account = await prisma.account.findUnique({
      where: { id: accountId },
      select: { createdAt: true },
    });
    if (!account) return false;
    const jours = (now.getTime() - account.createdAt.getTime()) / 86_400_000;
    if (jours < audience.registeredForDays) return false;
  }

  if (audience.isSubscriber !== undefined) {
    const abonne = await hasUnlimitedAccess(prisma, accountId, now);
    if (abonne !== audience.isSubscriber) return false;
  }

  if (audience.hasOrdered !== undefined) {
    const commandes = await prisma.printOrder.count({
      where: { orderedByAccountId: accountId, status: ORDERED },
    });
    if (commandes > 0 !== audience.hasOrdered) return false;
  }

  if (audience.minMemories !== undefined) {
    // Les souvenirs de **ses** carnets, photos exclues : une photo importée
    // n'est pas un récit, et « il raconte déjà » parle de récits.
    const souvenirs = await prisma.entry.count({
      where: { memo: { ownerAccountId: accountId }, kind: { not: "photo" } },
    });
    if (souvenirs < audience.minMemories) return false;
  }

  return true;
}
