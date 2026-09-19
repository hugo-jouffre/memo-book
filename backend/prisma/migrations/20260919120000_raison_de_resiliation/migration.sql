-- La raison invoquée à la résiliation (Hugo, 19/09/2026).
--
-- La feuille « Pourquoi nous quittes-tu ? » exige une réponse pour activer son
-- bouton, et cette réponse n'allait nulle part : le modèle de l'app la recevait
-- et la laissait tomber, faute de route. Elle se range désormais à côté de la
-- date de résiliation. Libre et facultative : c'est un sondage.
ALTER TABLE "subscriptions" ADD COLUMN "cancellationReason" TEXT;
