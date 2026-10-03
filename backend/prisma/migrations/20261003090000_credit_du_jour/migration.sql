-- Le crédit du jour remplace les étapes offertes et les limites de souvenirs
-- (Hugo, 03/10/2026). Tout le monde raconte gratuitement, 5 minutes par jour
-- et par voyage ; l'abonnement mensuel rend le récit illimité.
--
-- Le code d'avant est sur la branche `icebox/abonnement-hebdomadaire`.
--
-- ⚠️ **Rien n'est supprimé de `accounts` ici, et c'est voulu.** Railway migre
-- en pre-deploy pendant que l'ancien code sert encore le trafic : il lit
-- `offeredSteps`, `remainingSteps` et les trois colonnes des limites de
-- souvenirs à chaque requête authentifiée. Les supprimer dans ce déploiement
-- ferait répondre 500 à toute l'app le temps de la bascule. Le schéma Prisma
-- ne les connaît déjà plus ; la migration suivante, livrée une fois ce code en
-- service, les retire de la base.

-- La notification « fin des 3 étapes offertes » n'existe plus. Ses envois déjà
-- journalisés partent avec elle : une valeur d'énumération ne se retire pas
-- d'un type Postgres tant qu'une ligne la porte.
DELETE FROM "notification_deliveries" WHERE "kind" = 'trial_end';

-- AlterEnum
BEGIN;
CREATE TYPE "NotificationKind_new" AS ENUM ('trip_end', 'renewal_reminder', 'trip_end_email', 'writing_reminder', 'unordered_book', 'new_story', 'weekly_digest', 'school_holidays', 'learned_period', 'birthday');
ALTER TABLE "notification_deliveries" ALTER COLUMN "kind" TYPE "NotificationKind_new" USING ("kind"::text::"NotificationKind_new");
ALTER TYPE "NotificationKind" RENAME TO "NotificationKind_old";
ALTER TYPE "NotificationKind_new" RENAME TO "NotificationKind";
DROP TYPE "NotificationKind_old";
COMMIT;

-- AlterTable
ALTER TABLE "subscriptions" ALTER COLUMN "interval" SET DEFAULT 'month';

-- CreateTable
CREATE TABLE "trip_daily_usage" (
    "memoId" TEXT NOT NULL,
    "day" DATE NOT NULL,
    "usedMs" INTEGER NOT NULL DEFAULT 0,
    "voiceMs" INTEGER NOT NULL DEFAULT 0,
    "textCharacters" INTEGER NOT NULL DEFAULT 0,
    "limitNotifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "trip_daily_usage_pkey" PRIMARY KEY ("memoId","day")
);

-- AddForeignKey
ALTER TABLE "trip_daily_usage" ADD CONSTRAINT "trip_daily_usage_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;
