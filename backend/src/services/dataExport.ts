import type { DataExport, PrismaClient } from "@prisma/client";
import { randomBytes } from "node:crypto";
import type { AppContext } from "../context.js";
import { hashSessionToken } from "../lib/auth.js";
import { HttpError } from "../lib/httpError.js";

/**
 * « Exporter mes données », côté serveur — le droit d'accès et le droit à la
 * portabilité du RGPD (articles 15 et 20).
 *
 * Deux temps, et c'est tout le parti pris :
 *
 *  1. **La demande** (`POST /v1/accounts/me/export`) ne fabrique rien. Elle
 *     tire un secret, n'en garde que l'empreinte, et envoie par e-mail un lien
 *     valable sept jours.
 *  2. **Le lien** mène à une page de l'API (`routes/dataExportPage.ts`) qui
 *     résume l'archive, et dont le bouton la télécharge. C'est **là** que le
 *     ZIP se compose, à la volée, depuis la base et le stockage — voir
 *     `dataExportArchive.ts`.
 *
 * `docs/emails.md` prévoyait l'inverse : un job qui écrit le ZIP dans le
 * stockage, et un lien signé vers lui. Trois raisons de ne pas le faire :
 *
 *  - **le plan gratuit de Supabase refuse tout fichier de plus de 50 Mo**, et
 *    l'archive d'un voyageur qui a pris des photos les dépasse vite ;
 *  - une archive préparée est **une copie de tout ce qu'on sait de
 *    quelqu'un**, qui dort sept jours dans un bucket, qu'il faut penser à
 *    effacer, et que la suppression du compte doit aussi retrouver ;
 *  - elle est **périmée** dès qu'elle est écrite : un souvenir raconté après la
 *    demande n'y serait pas.
 *
 * Le prix à payer : chaque téléchargement repasse par l'API, dans la limite de
 * quinze minutes que Railway laisse à une requête — plus d'un gigaoctet sur
 * une connexion lente. Le lien sert donc plusieurs fois : un téléchargement
 * interrompu se relance.
 */

/** Combien de temps le lien de l'e-mail reste bon. */
export const DATA_EXPORT_TTL_DAYS = 7;

/**
 * Une demande qui suit la précédente de moins de cinq minutes **n'envoie
 * rien** : l'e-mail est en route, et un second ne ferait qu'invalider le
 * premier pendant qu'on le cherche dans sa boîte. Ça borne aussi ce qu'une
 * session volée peut faire de la boîte de quelqu'un.
 */
export const DATA_EXPORT_COOLDOWN_MINUTES = 5;

/**
 * Au-delà, le lien ne sert plus : un téléchargement interrompu se relance
 * quelques fois, pas vingt. Un lien qui a tant servi a sans doute fuité.
 */
export const DATA_EXPORT_MAX_DOWNLOADS = 20;

/** Le compte n'a pas d'adresse où envoyer le lien (Apple, adresse refusée). */
export const NO_EMAIL_CODE = "no_email";

/** Resend a refusé l'envoi : rien n'est parti, la demande peut se refaire. */
export const EMAIL_UNAVAILABLE_CODE = "email_unavailable";

export function dataExportExpiry(from: Date = new Date()): Date {
  return new Date(from.getTime() + DATA_EXPORT_TTL_DAYS * 24 * 60 * 60 * 1000);
}

/** Même forme qu'un token de session : opaque, tiré au hasard, stocké haché. */
function generateExportToken(): string {
  return randomBytes(32).toString("base64url");
}

/** Ce que l'app affiche une fois la demande partie. */
export interface DataExportReceipt {
  /** L'adresse à laquelle le lien est parti. */
  email: string;
  requestedAt: Date;
  expiresAt: Date;
  /**
   * Un e-mail était déjà parti il y a moins de cinq minutes : rien n'a été
   * renvoyé. L'app le dit autrement — « regarde aussi tes indésirables ».
   */
  alreadyRequested: boolean;
}

/**
 * Envoie à l'adresse du compte le lien de téléchargement de ses données.
 *
 * **À l'adresse du compte, et à elle seule** (`docs/emails.md` § 5) : la
 * requête n'en porte aucune, si bien qu'une session volée ne peut pas faire
 * partir les données de quelqu'un ailleurs que dans sa propre boîte.
 *
 * Le lien précédent n'est retiré **qu'une fois l'e-mail parti** : un envoi
 * raté ne doit pas couper un lien qui marche encore. Et la ligne d'un envoi
 * raté est effacée — sans quoi elle passerait pour une demande « déjà
 * partie », et bloquerait la suivante cinq minutes pour rien.
 */
export async function requestDataExport(
  context: AppContext,
  accountId: string,
  now: Date = new Date(),
): Promise<DataExportReceipt> {
  const { prisma, mailer, logger } = context;

  const account = await prisma.account.findUnique({
    where: { id: accountId },
    select: { email: true, firstName: true },
  });
  if (!account) throw HttpError.unauthorized();

  if (!account.email) {
    throw new HttpError(
      409,
      "Ton compte n’a pas d’adresse e-mail où t’envoyer tes données. Écris-nous depuis « Besoin d’aide ? » : on te les fera parvenir autrement.",
      NO_EMAIL_CODE,
    );
  }

  const recent = await prisma.dataExport.findFirst({
    where: {
      accountId,
      revokedAt: null,
      createdAt: { gt: new Date(now.getTime() - DATA_EXPORT_COOLDOWN_MINUTES * 60 * 1000) },
    },
    orderBy: { createdAt: "desc" },
  });
  if (recent) {
    return {
      email: recent.email,
      requestedAt: recent.createdAt,
      expiresAt: recent.expiresAt,
      alreadyRequested: true,
    };
  }

  const token = generateExportToken();
  const expiresAt = dataExportExpiry(now);
  const created = await prisma.dataExport.create({
    data: {
      accountId,
      tokenHash: hashSessionToken(token),
      email: account.email,
      expiresAt,
      createdAt: now,
    },
  });

  try {
    await mailer.sendDataExport({
      to: account.email,
      firstName: account.firstName,
      token,
      expiresAt,
    });
  } catch (cause: unknown) {
    await prisma.dataExport.delete({ where: { id: created.id } }).catch(() => {});
    logger.error({ err: cause, accountId }, "L’e-mail d’export des données n’est pas parti");
    throw new HttpError(
      503,
      "L’e-mail n’a pas pu partir. Réessaie dans un instant ; si ça continue, écris-nous depuis « Besoin d’aide ? ».",
      EMAIL_UNAVAILABLE_CODE,
    );
  }

  await prisma.dataExport.updateMany({
    where: { accountId, id: { not: created.id }, revokedAt: null },
    data: { revokedAt: now },
  });

  logger.info({ accountId, dataExportId: created.id }, "Lien d’export des données envoyé");

  return { email: account.email, requestedAt: now, expiresAt, alreadyRequested: false };
}

/** Ce que vaut le secret d'un lien d'export. */
export type DataExportLookup =
  | { status: "valid"; dataExport: DataExport }
  /** Inconnu, expiré, ou remplacé par une demande plus récente. */
  | { status: "invalid" }
  /** Bon, mais il a déjà servi `DATA_EXPORT_MAX_DOWNLOADS` fois. */
  | { status: "exhausted" };

/**
 * Retrouve la demande que désigne le secret d'un lien.
 *
 * Inconnu, expiré ou remplacé, c'est **un seul cas** : la personne n'y peut
 * rien de différent — elle redemande un export —, et détailler n'aiderait que
 * qui essaie des liens. Même règle que `resetPassword`.
 */
export async function findDataExport(
  prisma: PrismaClient,
  token: string,
  now: Date = new Date(),
): Promise<DataExportLookup> {
  if (token === "") return { status: "invalid" };

  const dataExport = await prisma.dataExport.findUnique({
    where: { tokenHash: hashSessionToken(token) },
  });

  if (!dataExport || dataExport.revokedAt || dataExport.expiresAt.getTime() <= now.getTime()) {
    return { status: "invalid" };
  }
  if (dataExport.downloadCount >= DATA_EXPORT_MAX_DOWNLOADS) {
    return { status: "exhausted" };
  }
  return { status: "valid", dataExport };
}

/** Compte un téléchargement — avant qu'il commence, pour que le plafond tienne. */
export async function recordDataExportDownload(
  prisma: PrismaClient,
  dataExportId: string,
  now: Date = new Date(),
): Promise<void> {
  await prisma.dataExport.update({
    where: { id: dataExportId },
    data: { downloadCount: { increment: 1 }, lastDownloadedAt: now },
  });
}
