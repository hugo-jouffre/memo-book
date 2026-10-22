-- Les jetons de Firebase Cloud Messaging, pour l'app Android (lot B3, 22/10/2026).
--
-- Additive : une énumération et une colonne avec défaut. Chaque jeton déjà
-- enregistré vient d'un iPhone et reste `apns` ; l'ancien code, qui ne connaît
-- pas la colonne, continue d'écrire des lignes que le défaut range du bon côté.

-- CreateEnum
CREATE TYPE "PushProvider" AS ENUM ('apns', 'fcm');

-- AlterTable
ALTER TABLE "push_tokens" ADD COLUMN "provider" "PushProvider" NOT NULL DEFAULT 'apns';
