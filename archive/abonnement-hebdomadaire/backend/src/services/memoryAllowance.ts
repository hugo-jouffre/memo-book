import type { MemoryPlan, PrismaClient } from "@prisma/client";
import { HttpError } from "../lib/httpError.js";
import { MEMORY_UPGRADE_WEEKLY_CENTS } from "./subscriptionCatalog.js";

/**
 * **Les limites de souvenirs** : ce qu'un compte peut raconter dans le mois, et
 * ce que ça coûte de raconter plus.
 *
 * À ne pas confondre avec les **étapes offertes** (`quota.ts`), qui sont le
 * palier d'entrée : trois étapes, une fois, puis l'abonnement. Les limites de
 * souvenirs sont le budget **hebdomadaire** de quelqu'un qui raconte **déjà** —
 * un abonné. Elles se rechargent toutes les semaines, et se relèvent contre
 * 3,99 €/semaine.
 *
 * **La semaine, parce que tout le produit est à la semaine** (Hugo,
 * 17/09/2026) : l'abonnement se facture ainsi, un voyage se compte ainsi, et
 * l'extension est une option du même produit. Un plafond mensuel derrière un
 * prix hebdomadaire aurait annoncé quatre fois le montant affiché.
 *
 * ⚠️ **On ne dit jamais « jetons » ni « tokens » dans l'app** (Hugo,
 * 16/09/2026). Le mot est « souvenirs », et l'unité aussi : l'app annonce
 * « 1 240 souvenirs sur 3 000 », pas un pourcentage de quota. Ce fichier est le
 * seul endroit où la conversion se fait ; l'app ne compte rien.
 *
 * **Pourquoi un vocal coûte plus qu'un message.** Parce qu'il coûte plus : une
 * minute de vocal passe par la transcription, la rédaction et la relecture, là
 * où un message écrit n'appelle que les deux dernières sur dix fois moins de
 * texte. Le rapport de dix est un ordre de grandeur, pas une mesure — il est à
 * réétalonner sur les factures OpenAI et Anthropic d'un mois plein, et c'est
 * pour ça qu'il vit ici, en une constante, plutôt que dispersé dans les routes.
 */

/** Ce qu'un message écrit consomme. L'unité de compte. */
export const TEXT_MEMORY_COST = 1;

/**
 * Ce qu'une **minute entamée** de vocal consomme.
 *
 * Entamée et non écoulée : une minute et une seconde en coûtent deux. C'est la
 * règle la plus facile à expliquer, et la seule qui ne récompense pas le
 * découpage d'un vocal en morceaux de 59 secondes.
 */
export const VOICE_MEMORY_COST_PER_MINUTE = 10;

/** Ce que chaque palier ouvre par semaine. */
export const MEMORY_ALLOWANCE: Record<MemoryPlan, number> = {
  // **200 minutes de vocal par semaine**, ou 2 000 messages — près de
  // 30 minutes de vocal par jour. Volontairement haut : cette limite n'est pas
  // un levier commercial, c'est un garde-fou contre l'usage qui coûterait plus
  // cher que l'abonnement. Un voyageur bavard qui raconte 20 minutes par jour
  // en consomme 1 400 : il ne doit jamais la voir bouger.
  included: 2_000,
  // Quatre fois plus, pour un voyage raconté à plusieurs, tous les jours.
  extended: 8_000,
};

/**
 * La durée d'une période, en jours. **Une semaine glissante**, comme la
 * facturation — voir `MEMORY_UPGRADE_WEEKLY_CENTS`.
 */
const PERIOD_DAYS = 7;

/** Le prix hebdomadaire du palier étendu, en centimes. Réexporté pour l'API. */
export const MEMORY_UPGRADE_CENTS = MEMORY_UPGRADE_WEEKLY_CENTS;

export type MemorySnapshot = {
  plan: MemoryPlan;
  used: number;
  allowance: number;
  /** Le jour où le budget se remet à zéro. */
  renewsOn: Date;
  upgradeWeeklyPrice: number;
};

/**
 * Ce qu'une durée de vocal coûte, en souvenirs.
 *
 * Une durée absente coûte une minute : un vocal dont on ignore la durée existe
 * quand même, et ne rien décompter reviendrait à offrir l'usage le plus cher à
 * qui ne transmet pas la métadonnée.
 */
export function voiceCost(durationSeconds: number | null | undefined): number {
  const seconds = durationSeconds ?? 60;
  const minutes = Math.max(1, Math.ceil(seconds / 60));
  return minutes * VOICE_MEMORY_COST_PER_MINUTE;
}

/**
 * Le début de période à retenir : celui qu'on a, ou aujourd'hui si la semaine
 * est écoulée.
 *
 * **Glissante et non calendaire** : un compte ouvert un samedi aurait sinon un
 * jour de budget pour sa première semaine, ce qui se lit comme un bogue et ne
 * se rattrape par aucune explication.
 */
function currentPeriodStart(start: Date, now: Date): Date {
  const elapsed = now.getTime() - start.getTime();
  const period = PERIOD_DAYS * 24 * 60 * 60 * 1000;
  if (elapsed < period) return start;

  // On saute les périodes entières écoulées d'un coup plutôt que de repartir de
  // maintenant : le jour de renouvellement reste le même d'une semaine à
  // l'autre, même après un mois sans ouvrir l'app.
  const skipped = Math.floor(elapsed / period);
  return new Date(start.getTime() + skipped * period);
}

/** Le jour où le budget se remet à zéro. */
function periodEnd(start: Date): Date {
  return new Date(start.getTime() + PERIOD_DAYS * 24 * 60 * 60 * 1000);
}

/**
 * Où en est un compte, **période remise à jour si elle a expiré**.
 *
 * La remise à zéro a lieu à la lecture et non par une tâche planifiée : un
 * budget hebdomadaire n'a pas besoin d'être exact à la seconde, il a besoin
 * d'être juste au moment où quelqu'un le regarde ou le consomme. Une tâche de
 * plus pour ça serait une pièce mobile de plus à surveiller.
 */
export async function readMemoryAllowance(
  prisma: PrismaClient,
  accountId: string,
): Promise<MemorySnapshot> {
  const account = await prisma.account.findUniqueOrThrow({
    where: { id: accountId },
    select: { memoryPlan: true, memoryUsed: true, memoryPeriodStart: true },
  });

  const now = new Date();
  const start = currentPeriodStart(account.memoryPeriodStart, now);
  const isNewPeriod = start.getTime() !== account.memoryPeriodStart.getTime();

  if (isNewPeriod) {
    await prisma.account.update({
      where: { id: accountId },
      data: { memoryPeriodStart: start, memoryUsed: 0 },
    });
  }

  return {
    plan: account.memoryPlan,
    used: isNewPeriod ? 0 : account.memoryUsed,
    allowance: MEMORY_ALLOWANCE[account.memoryPlan],
    renewsOn: periodEnd(start),
    upgradeWeeklyPrice: MEMORY_UPGRADE_CENTS,
  };
}

/**
 * Décompte, et refuse quand il ne reste rien.
 *
 * **Le refus porte un code que l'app sait lire** (`memory_limit_reached`) :
 * c'est lui qui ouvre la feuille d'extension plutôt qu'un bandeau d'erreur. Un
 * 403 muet aurait envoyé quelqu'un au support pour une limite qui s'achète en
 * deux gestes.
 *
 * On décompte **après** avoir vérifié, dans la même écriture : deux vocaux
 * envoyés en même temps ne doivent pas passer tous les deux sur le dernier
 * souvenir disponible. `increment` fait l'addition côté base, donc sans course.
 */
export async function consumeMemory(
  prisma: PrismaClient,
  accountId: string,
  cost: number,
): Promise<void> {
  if (cost <= 0) return;

  const snapshot = await readMemoryAllowance(prisma, accountId);
  if (snapshot.used + cost > snapshot.allowance) {
    throw new HttpError(
      403,
      "Tu as atteint tes limites de souvenirs pour cette semaine. Étends-les pour continuer à raconter.",
      "memory_limit_reached",
    );
  }

  await prisma.account.update({
    where: { id: accountId },
    data: { memoryUsed: { increment: cost } },
  });
}

/**
 * Passe au palier étendu.
 *
 * ⚠️ **Aucun encaissement ici.** Comme l'abonnement lui-même, l'extension est
 * un service numérique : Apple impose l'achat intégré, et c'est StoreKit qui
 * portera la transaction. Cette route pose le palier, ce qui permet de
 * dérouler le parcours de bout en bout dans l'app ; le jour où StoreKit est
 * branché, c'est son reçu qui l'appelle.
 */
export async function setMemoryPlan(
  prisma: PrismaClient,
  accountId: string,
  plan: MemoryPlan,
): Promise<MemorySnapshot> {
  await prisma.account.update({ where: { id: accountId }, data: { memoryPlan: plan } });
  return readMemoryAllowance(prisma, accountId);
}
