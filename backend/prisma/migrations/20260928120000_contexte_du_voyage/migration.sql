-- Le contexte du voyage, recueilli par MEMO avant la première étape.
ALTER TYPE "ChatDisposition" ADD VALUE 'trip_context';

ALTER TABLE "memos" ADD COLUMN "tripContext" JSONB;
