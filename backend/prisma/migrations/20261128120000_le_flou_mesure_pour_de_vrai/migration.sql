-- Le flou, mesuré pour de vrai (T310).
--
-- `entries.photoSharpness` porte mal son nom : elle mesure le contraste et ne
-- voit pas le flou. Cette colonne-ci le mesure, de 0 (nette) à 1 (bouillie).
-- NULL partout au départ : aucune photo déjà reçue n'a été mesurée, et on ne
-- devine pas. Rien ne la lit encore — elle attend d'être calibrée sur un lot
-- réel avant qu'un seuil en tire une phrase pour le voyageur.

-- AlterTable
ALTER TABLE "entries" ADD COLUMN     "photoBlur" DOUBLE PRECISION;
