import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { replyToOf } from "../services/mailer.js";

/**
 * **La page publique de suppression d'un compte** — que Google Play exige de
 * toute app qui crée des comptes (lot B6, `docs/android.md`) : une adresse
 * web, ouvrable sans l'app, qui dit comment supprimer son compte et ce qui
 * part avec lui. Son URL se déclare dans la Play Console (*Contenu de
 * l'application ▸ Sécurité des données*).
 *
 * **Deux chemins, et l'app d'abord.** Dans l'app, *Profil ▸ Supprimer mon
 * compte* efface tout, tout de suite (`DELETE /v1/account`,
 * `services/deletion.ts`). Sans l'app — téléphone perdu, app désinstallée —,
 * un e-mail depuis l'adresse du compte : c'est elle qui prouve que la demande
 * vient de son titulaire, sans formulaire qui permettrait de supprimer le
 * compte de quelqu'un d'autre.
 *
 * Ce que la page dit de ce qui part et de ce qui reste suit
 * `deleteAccountAndData` : un voyage partagé passe au co-voyageur le plus
 * ancien, avec ses commandes, détachées du compte ; tout le reste part.
 */

const COLORS = {
  background: "#FCF2E9",
  paper: "#FFFCF8",
  ink: "#2D231A",
  inkMuted: "#8A8078",
  action: "#28654B",
  onAction: "#FFFCF8",
};

/** Le chemin de la page, à déclarer dans la Play Console. */
export const ACCOUNT_DELETION_PATH = "/account/delete";

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/** Le lien « écrire » de la page : l'adresse de réponse, l'objet et le corps déjà posés. */
export function deletionRequestMailto(address: string): string {
  const subject = "Supprimer mon compte MemoBook";
  const body =
    "Bonjour,\n\nJe souhaite supprimer mon compte MemoBook et les données qui y sont liées.\n\n" +
    "(Envoie ce message depuis l’adresse e-mail de ton compte.)";
  return `mailto:${address}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

export function renderAccountDeletionPage(contactAddress: string): string {
  const address = escapeHtml(contactAddress);
  const mailto = escapeHtml(deletionRequestMailto(contactAddress));
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Supprimer ton compte MemoBook</title>
<style>
  body { margin:0; background:${COLORS.background}; color:${COLORS.ink};
    font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif; }
  main { max-width:560px; margin:32px auto; padding:0 16px; }
  .card { background:${COLORS.paper}; border-radius:20px; overflow:hidden; }
  .brand { background:${COLORS.action}; color:${COLORS.onAction}; text-align:center; padding:40px 24px;
    font-family:Georgia,'Times New Roman',serif; font-size:36px; line-height:36px; font-weight:700; letter-spacing:2px; }
  .body { padding:32px 24px; }
  h1 { margin:0 0 16px; font-size:22px; line-height:28px; }
  h2 { margin:28px 0 8px; font-size:17px; line-height:24px; }
  p, li { font-size:15px; line-height:22px; }
  p { margin:0 0 16px; }
  ul, ol { margin:0 0 16px; padding-left:22px; }
  .muted { color:${COLORS.inkMuted}; font-size:13px; line-height:18px; }
  .button { display:block; text-align:center; background:${COLORS.action}; color:${COLORS.onAction};
    text-decoration:none; font-size:15px; font-weight:600; line-height:20px; padding:14px 28px;
    border-radius:12px; margin:16px 0; }
</style>
</head>
<body>
<main><div class="card">
<div class="brand">MEMO<br>BOOK</div>
<div class="body">
<h1>Supprimer ton compte MemoBook</h1>
<p>Tu peux supprimer ton compte et les données qui y sont liées à tout moment, depuis l’app ou sans elle.</p>

<h2>Depuis l’app</h2>
<ol>
<li>Ouvre MemoBook, sur iPhone ou sur Android.</li>
<li>Touche ta photo pour ouvrir ton <strong>Profil</strong>.</li>
<li>Tout en bas, touche <strong>Supprimer mon compte</strong>, puis confirme.</li>
</ol>
<p>La suppression est immédiate et définitive.</p>

<h2>Sans l’app</h2>
<p>Écris-nous <strong>depuis l’adresse e-mail de ton compte</strong> : c’est elle qui nous permet de vérifier que la demande vient bien de toi. On supprime le compte sous 30 jours, et on te le confirme par e-mail.</p>
<a class="button" href="${mailto}">Demander la suppression par e-mail</a>
<p class="muted">Adresse : ${address}</p>

<h2>Ce qui est supprimé</h2>
<ul>
<li>Ton compte : nom, adresse e-mail, mot de passe, photo, date de naissance, adresse postale.</li>
<li>Les voyages que tu es seul·e à raconter, avec leurs vocaux, photos, textes, carnets et commandes.</li>
<li>Ta participation aux voyages des autres.</li>
<li>Tes moyens de paiement enregistrés, ta cagnotte, tes appareils, tes notifications et tes réglages.</li>
</ul>

<h2>Ce qui est conservé</h2>
<ul>
<li>Un voyage raconté à plusieurs reste à tes co-voyageurs : il passe au plus ancien d’entre eux, avec ce qui y a été raconté et ses commandes, qui ne sont plus liées à ton compte.</li>
<li>Les paiements déjà faits restent dans les registres de notre prestataire de paiement (Stripe) et du store, qui les gardent pour leurs propres obligations légales.</li>
</ul>
<p class="muted">Un abonnement en cours se résilie à part, depuis le store qui l’a vendu (App Store ou Google Play) : supprimer le compte n’arrête pas sa facturation.</p>
</div>
</div></main>
</body>
</html>`;
}

export function registerAccountDeletionPageRoutes(app: FastifyInstance, context: AppContext): void {
  app.get(ACCOUNT_DELETION_PATH, async (_request, reply) =>
    reply
      .header("Cache-Control", "public, max-age=3600")
      .type("text/html; charset=utf-8")
      .send(renderAccountDeletionPage(replyToOf(context.env.MAIL_FROM))),
  );
}
