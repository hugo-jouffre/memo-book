-- **Les stickers découpés dans tes vraies photos** (Hugo, 10/11/2026) —
-- « stickers découpés depuis tes vraies photos de billets et tampons ».
--
-- Un billet de train, un tampon de passeport, une étiquette de bagage : ce
-- sont des souvenirs plats, qui font de mauvaises photos pleine page et
-- d'excellents stickers. On les découpe **dans la photo du voyageur** — son
-- billet reste son billet, avec ses vraies dates — plutôt que de les faire
-- redessiner par un modèle d'images, qui en réinventerait le texte.

-- Ce qu'on a découpé, une fois pour toutes : le découpage coûte un appel au
-- modèle et du calcul, et un carnet se recompose souvent.
CREATE TABLE "photo_stickers" (
    "id" TEXT NOT NULL,
    "memoId" TEXT NOT NULL,
    "entryId" TEXT NOT NULL,
    -- La clé du PNG détouré dans le stockage, `sticker/<uuid>.png`.
    "storageKey" TEXT NOT NULL,
    -- Ce que le modèle a reconnu : « billet de train », « tampon de passeport ».
    -- Lisible, et c'est ce qui s'écrit dans le journal de composition.
    "label" TEXT NOT NULL,
    -- De 0 à 100 : à quel point ça fait un bon sticker.
    "score" INTEGER NOT NULL,
    "widthPx" INTEGER NOT NULL,
    "heightPx" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "photo_stickers_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "photo_stickers_storageKey_key" ON "photo_stickers"("storageKey");

-- **Un sticker par photo.** La photo est la source ; la redécouper donnerait
-- le même dessin, et le poserait deux fois dans le carnet.
CREATE UNIQUE INDEX "photo_stickers_entryId_key" ON "photo_stickers"("entryId");

CREATE INDEX "photo_stickers_memoId_idx" ON "photo_stickers"("memoId");

ALTER TABLE "photo_stickers" ADD CONSTRAINT "photo_stickers_memoId_fkey"
    FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "photo_stickers" ADD CONSTRAINT "photo_stickers_entryId_fkey"
    FOREIGN KEY ("entryId") REFERENCES "entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- **On a regardé cette photo**, et on ne la regardera plus : qu'on en ait
-- tiré un sticker ou non. Sans cette date, chaque composition rappellerait le
-- modèle sur les mêmes paysages pour s'entendre répondre « rien à découper ».
ALTER TABLE "entries" ADD COLUMN "stickerCheckedAt" TIMESTAMP(3);
