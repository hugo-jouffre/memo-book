import type { Account, MemoNotificationPreference, PrismaClient } from "@prisma/client";

/**
 * **Les alertes de chacun** — D13 (Hugo, 19/10/2026).
 *
 * Deux jeux d'interrupteurs, et chacun n'appartient qu'à un compte :
 *
 * - **ceux d'un voyage** — l'interrupteur « Notifications » des réglages du
 *   voyage et les quatre alertes de « Gérer mes notifications » —, une ligne
 *   de `memo_notification_preferences` par (voyage, compte). Ils valaient pour
 *   tous les co-voyageurs : un seul qui coupait la relance d'écriture la
 *   coupait chez tout le monde ;
 * - **ceux du compte** — les notifications qui ne parlent d'aucun voyage —,
 *   des colonnes de `accounts`, réglées depuis la ligne « Notifications » du
 *   profil.
 *
 * **Pas de ligne, tout est allumé** : on n'en écrit une qu'au premier réglage.
 */

/** Les alertes d'un voyage, pour un voyageur. */
export interface TripNotificationPreferences {
  notificationsEnabled: boolean;
  notifyWritingReminder: boolean;
  notifyNewStory: boolean;
  notifyWeeklyDigest: boolean;
  notifyTripEnd: boolean;
}

export const DEFAULT_TRIP_NOTIFICATION_PREFERENCES: Readonly<TripNotificationPreferences> = Object.freeze({
  notificationsEnabled: true,
  notifyWritingReminder: true,
  notifyNewStory: true,
  notifyWeeklyDigest: true,
  notifyTripEnd: true,
});

type Db = Pick<PrismaClient, "memoNotificationPreference">;

/** Ce que dit une ligne — ou les valeurs par défaut, sans ligne. */
export function pickTripNotificationPreferences(
  row: MemoNotificationPreference | null | undefined,
): TripNotificationPreferences {
  if (!row) return { ...DEFAULT_TRIP_NOTIFICATION_PREFERENCES };
  return {
    notificationsEnabled: row.notificationsEnabled,
    notifyWritingReminder: row.notifyWritingReminder,
    notifyNewStory: row.notifyNewStory,
    notifyWeeklyDigest: row.notifyWeeklyDigest,
    notifyTripEnd: row.notifyTripEnd,
  };
}

/** Les alertes que **ce compte** a réglées pour ce voyage. */
export async function readTripNotificationPreferences(
  prisma: Db,
  memoId: string,
  accountId: string,
): Promise<TripNotificationPreferences> {
  const row = await prisma.memoNotificationPreference.findUnique({
    where: { memoId_accountId: { memoId, accountId } },
  });
  return pickTripNotificationPreferences(row);
}

/**
 * Les alertes de ce compte pour chacun de ces voyages, d'une requête — la
 * passe des notifications lit tous ses voyages d'un coup.
 */
export async function tripNotificationPreferencesOf(
  prisma: Db,
  accountId: string,
  memoIds: string[],
): Promise<(memoId: string) => TripNotificationPreferences> {
  const rows =
    memoIds.length === 0
      ? []
      : await prisma.memoNotificationPreference.findMany({ where: { accountId, memoId: { in: memoIds } } });
  const byMemo = new Map(rows.map((row) => [row.memoId, row]));
  return (memoId) => pickTripNotificationPreferences(byMemo.get(memoId));
}

/**
 * Écrit ce que ce compte change à ses alertes du voyage — **les siennes
 * seulement** : celles des co-voyageurs ne bougent pas. Un champ absent n'est
 * pas touché ; la première écriture crée la ligne sur les valeurs par défaut.
 */
export async function writeTripNotificationPreferences(
  prisma: Db,
  memoId: string,
  accountId: string,
  patch: Partial<TripNotificationPreferences>,
): Promise<void> {
  if (Object.values(patch).every((value) => value === undefined)) return;
  await prisma.memoNotificationPreference.upsert({
    where: { memoId_accountId: { memoId, accountId } },
    create: { memoId, accountId, ...DEFAULT_TRIP_NOTIFICATION_PREFERENCES, ...patch },
    update: patch,
  });
}

/** Les notifications du compte — celles qui ne parlent d'aucun voyage. */
export type AccountNotificationPreferences = Pick<
  Account,
  "notifyRenewalReminder" | "notifySchoolHolidays" | "notifyLearnedPeriod" | "notifyBirthday"
>;

/**
 * La forme que l'app lit — `AccountNotificationPreferences` de
 * `MemoBookCore`, au nom près. La même pour la réponse et le `PATCH`.
 */
export function serializeAccountNotificationPreferences(account: AccountNotificationPreferences) {
  return {
    renewalReminder: account.notifyRenewalReminder,
    schoolHolidays: account.notifySchoolHolidays,
    learnedPeriod: account.notifyLearnedPeriod,
    birthday: account.notifyBirthday,
  };
}

export function accountNotificationColumns(body: ReturnType<typeof serializeAccountNotificationPreferences>) {
  return {
    notifyRenewalReminder: body.renewalReminder,
    notifySchoolHolidays: body.schoolHolidays,
    notifyLearnedPeriod: body.learnedPeriod,
    notifyBirthday: body.birthday,
  };
}
