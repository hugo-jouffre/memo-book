-- Les étapes et les chiffres d'un vrai voyage (T227, Hugo 06/10/2026) : seul
-- le jeu d'essai écrivait `memo_steps`, la destination et les compteurs du
-- voyage. `services/tripFacts.ts` les déduit désormais des souvenirs, et la
-- destination déduite doit pouvoir suivre les souvenirs sans jamais écraser
-- une destination posée : ce drapeau dit laquelle des deux on a.
--
-- Additive : une colonne avec une valeur par défaut, rien de retiré. Les
-- voyages existants gardent leur destination (posée, donc `false`).

-- AlterTable
ALTER TABLE "memos" ADD COLUMN "destinationInferred" BOOLEAN NOT NULL DEFAULT false;
