-- Le rythme du récit sous sa clé, et non sous le libellé de l'écran (Hugo,
-- 18/09/2026).
--
-- Jusqu'au 17/09/2026 la création d'un voyage écrivait « Tous les jours »,
-- « Tous les 2 jours » ou « Toutes les semaines » là où la feuille des
-- réglages écrivait déjà `daily`, `every_two_days`, `weekly`. L'app décode la
-- colonne en énumération : ces dix voyages s'affichaient sous leur libellé
-- brut et la feuille « Rythme du récit » ne cochait rien. Voir
-- `services/narrationPace.ts`, qui normalise désormais tout ce qui entre.
UPDATE "memos" SET "narrationPace" = 'daily'          WHERE lower(trim("narrationPace")) = 'tous les jours';
UPDATE "memos" SET "narrationPace" = 'every_two_days' WHERE lower(trim("narrationPace")) IN ('tous les 2 jours', 'tous les deux jours');
UPDATE "memos" SET "narrationPace" = 'every_three_days' WHERE lower(trim("narrationPace")) IN ('tous les 3 jours', 'tous les trois jours');
UPDATE "memos" SET "narrationPace" = 'weekly'         WHERE lower(trim("narrationPace")) IN ('toutes les semaines', 'une fois par semaine');
UPDATE "memos" SET "narrationPace" = 'custom'         WHERE lower(trim("narrationPace")) = 'personnalisé';
UPDATE "memos" SET "narrationPace" = 'by_place'       WHERE lower(trim("narrationPace")) = 'à chaque lieu';
