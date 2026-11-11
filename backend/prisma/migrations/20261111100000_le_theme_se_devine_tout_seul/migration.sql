-- **Le thème se devine tout seul** (Hugo, 10/11/2026) — « le thème de
-- l'aventure devrait être déterminé automatiquement au bout de quelques
-- étapes, et si aucun ne match, le chat devrait le demander subtilement ».
--
-- Cette date retient que MEMO a déjà posé la question, pour qu'il ne la pose
-- jamais deux fois. Elle ne s'efface pas quand le thème finit par être posé :
-- ce qu'on garde, c'est qu'on a demandé, pas qu'on attend.
--
-- Nulle par défaut : à personne on n'a encore demandé.
ALTER TABLE "memos" ADD COLUMN "themeAskedAt" TIMESTAMP(3);
