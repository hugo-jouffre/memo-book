-- L'aperçu léger d'une photo, le temps que la pleine définition monte (T309).
-- `false` partout : tout ce qui existe est déjà en pleine définition.

-- AlterTable
ALTER TABLE "media_assets" ADD COLUMN     "isLightweight" BOOLEAN NOT NULL DEFAULT false;
