-- Le jour que le récit raconte, et non celui où on l'a enregistré (T308).
-- Nuls partout à la création : aucun récit d'avant n'a été lu pour ça, et un
-- jour inventé serait pire que pas de jour.

-- AlterTable
ALTER TABLE "entries" ADD COLUMN     "livedFromDay" DATE,
ADD COLUMN     "livedToDay" DATE;

-- AlterTable
ALTER TABLE "memo_steps" ADD COLUMN     "livedFromDay" DATE,
ADD COLUMN     "livedToDay" DATE;
