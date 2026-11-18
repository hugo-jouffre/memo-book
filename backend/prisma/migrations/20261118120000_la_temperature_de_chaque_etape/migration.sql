-- **La température de chaque étape** (T263, Hugo : « chaque étape devrait
-- porter sa date et sa température, avec une petite icône météo »).
--
-- Deux origines, et la hiérarchie compte :
--
--   `entries.temperatureC`    ce que le voyageur a DIT dans son vocal, relevé
--                             par la rédaction comme l'est déjà `weatherKey`.
--                             C'est un souvenir, et il l'emporte.
--   `memo_steps.temperatureC` ce qu'on a CHERCHÉ chez Visual Crossing à partir
--                             du nom du lieu et de la date, faute de l'avoir
--                             entendu. Gardé : une température passée ne
--                             change plus.
--
-- `temperatureLookedUpAt` sépare « jamais cherché » de « cherché, rien
-- trouvé » : sans lui, une étape dont le lieu est introuvable serait
-- réinterrogée à chaque lecture du voyage, et le service a un quota.
--
-- Entières : personne ne dit « il faisait 23,4 degrés ». Négatives l'hiver.
ALTER TABLE "entries" ADD COLUMN "temperatureC" INTEGER;
ALTER TABLE "memo_steps" ADD COLUMN "temperatureC" INTEGER;
ALTER TABLE "memo_steps" ADD COLUMN "temperatureLookedUpAt" TIMESTAMP(3);
