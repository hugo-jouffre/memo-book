import { existsSync } from "node:fs";
import { z } from "zod";

/**
 * Variable facultative. Dans un `.env`, `MA_VARIABLE=` veut dire « pas
 * configurée » — pas « chaîne vide ». Sans cette nuance, une ligne laissée en
 * attente empêche le serveur de démarrer avec un message qui accuse le format
 * plutôt que l'absence.
 */
function optional<T extends z.ZodTypeAny>(inner: T) {
  return z.preprocess((value) => (value === "" ? undefined : value), inner.optional());
}

/** Toujours résolu depuis la racine du back-end, pas du dossier courant. */
const ENV_FILE = new URL("../.env", import.meta.url).pathname;

/**
 * Toute la configuration passe par ici. Le serveur refuse de démarrer si une
 * variable requise manque, plutôt que d'échouer plus tard au milieu d'un job.
 */
const schema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  LOG_LEVEL: z
    .enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"])
    .default("info"),

  DATABASE_URL: z.string().min(1),
  /**
   * Connexions Postgres qu'un process peut ouvrir, Prisma et pg-boss compris.
   * Le Session pooler de Supabase n'en accepte que 15 pour tout le projet :
   * ce budget laisse tourner un serveur, un worker et un `prisma studio` sans
   * que le 16ᵉ client soit refusé. Voir `lib/databasePool.ts`.
   */
  DATABASE_POOL_SIZE: z.coerce.number().int().min(2).max(50).default(5),

  // Optionnels ici, vérifiés au moment de construire le client dans
  // `createMediaStorage`. En test et pendant le smoke, le stockage est en
  // mémoire : exiger un bucket pour lancer les tests serait une friction
  // gratuite, et un défaut silencieux masquerait une erreur de configuration
  // en production.
  S3_ENDPOINT: optional(z.string().url()),
  S3_REGION: z.string().default("us-east-1"),
  S3_BUCKET: optional(z.string().min(1)),
  S3_ACCESS_KEY_ID: optional(z.string().min(1)),
  S3_SECRET_ACCESS_KEY: optional(z.string().min(1)),
  S3_FORCE_PATH_STYLE: z
    .enum(["true", "false"])
    .default("true")
    .transform((value) => value === "true"),

  /**
   * Audiences attendues dans les jetons d'identité. Un jeton signé par Apple
   * mais émis pour une autre app ne doit pas ouvrir de compte ici : c'est le
   * `aud` qui le dit, et il n'a de sens que comparé à ces valeurs.
   *
   * Vides en dehors de la production : les tests passent un vérificateur
   * simulé, et exiger ces variables pour lancer la suite serait une friction
   * gratuite. Les routes concernées échouent clairement si elles manquent.
   */
  APPLE_BUNDLE_ID: z.string().default(""),
  GOOGLE_IOS_CLIENT_ID: z.string().default(""),
  /** Le client web, si un jour l'app tourne aussi dans un navigateur. */
  GOOGLE_WEB_CLIENT_ID: z.string().default(""),

  OPENAI_API_KEY: z.string().default(""),
  OPENAI_TRANSCRIPTION_MODEL: z.string().default("gpt-4o-transcribe"),
  OPENAI_STRUCTURING_MODEL: z.string().default("gpt-4o"),

  /**
   * Rédaction du texte de carnet. Séparée d'OpenAI, qui reste sur la
   * transcription audio et la mise en page : la rédaction est l'étape où la
   * qualité se voit, et elle doit pouvoir changer de modèle sans toucher au
   * reste du pipeline.
   *
   * Sans clé, la rédaction bascule sur `FakeRedactor` même en mode `live` —
   * le carnet reste générable, avec un texte simplement nettoyé.
   */
  ANTHROPIC_API_KEY: z.string().default(""),
  ANTHROPIC_REDACTION_MODEL: z.string().default("claude-opus-5"),
  /**
   * La voix de MEMO dans le chat — `docs/conversation.md`. Un modèle plus
   * rapide que la rédaction : un tour se joue en quelques secondes, sous les
   * yeux du voyageur. Sans clé, le moteur de règles répond.
   */
  ANTHROPIC_CONVERSATION_MODEL: z.string().default("claude-sonnet-5"),
  /**
   * Le plafond anti-abus de la conversation : des tours du voyageur par
   * carnet et par jour UTC. Ferme la porte à un script, pas à un voyageur.
   */
  CHAT_DAILY_TURN_CAP: z.coerce.number().int().positive().default(150),

  PIPELINE_MODE: z.enum(["auto", "live", "fake"]).default("auto"),

  APITEMPLATE_API_KEY: z.string().default(""),
  APITEMPLATE_TEMPLATE_ID: z.string().default("7a177b23210099d6"),
  // Le compte MemoBook est hébergé en région DE. Pointer sur rest.apitemplate.io
  // renvoie une erreur d'authentification trompeuse.
  APITEMPLATE_BASE_URL: z.string().url().default("https://rest-de.apitemplate.io/v2"),

  /**
   * Axe distinct de `PIPELINE_MODE`, volontairement.
   *
   * `PIPELINE_MODE` pilote `live`, qui choisit aussi le transcripteur, le
   * structureur et Webflow. Or la boucle de travail sur la mise en page, c'est
   * « transcription simulée + vrai PDF » : seul un axe séparé l'exprime.
   * `auto` conserve exactement le comportement historique.
   */
  RENDERER: z.enum(["auto", "apitemplate", "local", "fake"]).default("auto"),
  RENDER_OUTPUT_DIR: z.string().default(".render-out"),
  RENDER_PUBLIC_BASE_URL: z.string().default(""),
  RENDER_PROFILE: z.enum(["print", "preview"]).default("preview"),

  /**
   * La racine des liens de prévisualisation publics — « https://memo-book.com ».
   *
   * C'est elle qui préfixe `/c/<slug>`, le lien qu'on envoie à ses proches pour
   * qu'ils suivent le carnet en direct. La page derrière n'existe pas encore ;
   * le lien, lui, doit déjà être stable, parce qu'il part dans des
   * conversations WhatsApp qu'on ne rattrape pas.
   */
  SHARE_PUBLIC_BASE_URL: z.string().default("https://memo-book.com"),

  /**
   * L'adresse publique de l'API elle-même, pour les liens qu'elle sert en
   * HTTP simple — les photos de profil (`GET /v1/avatars/:file`). Vide, on
   * retombe sur **`RAILWAY_PUBLIC_DOMAIN`**, que Railway pose tout seul sur le
   * service (`api-production-9f35a.up.railway.app`) ; puis sur
   * `APP_LINK_BASE_URL` quand il est en `https://` ; sinon sur
   * `http://localhost:3000`. Voir `services/avatars.ts` — rien à configurer
   * sur Railway.
   */
  API_PUBLIC_BASE_URL: z.string().default(""),
  RAILWAY_PUBLIC_DOMAIN: z.string().default(""),

  WEBFLOW_API_TOKEN: z.string().default(""),
  WEBFLOW_SITE_ID: z.string().default(""),

  /**
   * L'envoi d'e-mails passe par Resend, en HTTP — pas de SMTP, pas de
   * dépendance. Sans clé, les messages sont **journalisés et écrits sur le
   * disque** (`MAIL_OUTPUT_DIR`) au lieu de partir : c'est ce qui permet de
   * lire l'e-mail de « mot de passe oublié » en développement. Refusé en
   * production — voir `services/mailer.ts`.
   */
  RESEND_API_KEY: z.string().default(""),
  MAIL_FROM: z.string().default("MemoBook <bonjour@memo-book.com>"),
  MAIL_OUTPUT_DIR: z.string().default(".mail-out"),

  /**
   * La racine du lien du bouton « Réinitialiser mon mot de passe » dans
   * l'e-mail. Le chemin derrière est toujours `password/reset?token=…`.
   *
   * **En production, l'adresse publique de l'API** — par exemple
   * `https://api-production-9f35a.up.railway.app/`. Le lien mène alors à la
   * page `GET /password/reset` (`routes/passwordResetPage.ts`), qui ouvre
   * l'app par son schéma `memobook://`. Il le faut : un lien `memobook://`
   * écrit tel quel dans l'e-mail n'est **pas cliquable** dans Gmail et la
   * plupart des clients mail.
   *
   * La valeur par défaut, le schéma d'app lui-même, sert au développement :
   * le lien journalisé s'ouvre d'un `xcrun simctl openurl`. Le jour où ce
   * domaine sert un `apple-app-site-association`, le même lien deviendra
   * universel sans toucher au code.
   */
  APP_LINK_BASE_URL: z.string().default("memobook://"),

  /**
   * La feuille de bord Google Sheets (T72) : l'adresse du script Apps Script
   * déployé en application web (`backend/scripts/apps-script/StatsSheet.gs`),
   * et le secret qu'il attend dans chaque envoi. Vides, rien ne part et rien
   * n'échoue : le job quotidien se contente de journaliser.
   */
  STATS_SHEET_WEBHOOK_URL: z.string().default(""),
  STATS_SHEET_SECRET: z.string().default(""),

  /**
   * Stripe — encaissement des carnets imprimés et des recharges de cagnotte.
   *
   * **Jamais l'abonnement.** Celui-là est un service numérique : Apple impose
   * StoreKit, et le faire passer par Stripe depuis l'app ferait rejeter le
   * binaire. Voir `Subscription.provider`, qui porte les deux.
   *
   * Les trois clés ne viennent pas du même endroit :
   * - `STRIPE_SECRET_KEY` — *Développeurs ▸ Clés API*. **Secrète.**
   * - `STRIPE_PUBLISHABLE_KEY` — même écran, publique par construction : elle
   *   part dans l'app, comme `GOOGLE_IOS_CLIENT_ID`. Servie par le serveur
   *   plutôt que codée en dur, pour changer de compte sans livrer l'app.
   * - `STRIPE_WEBHOOK_SECRET` — *Développeurs ▸ Webhooks*, propre à **chaque**
   *   point de terminaison. Celui de `stripe listen` en local n'est pas celui
   *   de la production.
   *
   * En production, l'API refuse de démarrer sans les trois, et le worker sans
   * la clé secrète (`assertApiPaymentsConfigured`). Ailleurs, vides, c'est
   * l'encaissement simulé — qui ne croit aucun webhook hors de la suite de
   * tests.
   */
  STRIPE_SECRET_KEY: z.string().default(""),
  STRIPE_PUBLISHABLE_KEY: z.string().default(""),
  STRIPE_WEBHOOK_SECRET: z.string().default(""),

  /**
   * L'App Store — **l'abonnement**, acheté par StoreKit. Voir
   * `services/appStore.ts`.
   *
   * Aucun secret : vérifier une transaction ne demande que le certificat racine
   * d'Apple (`certs/apple/`), l'identifiant de l'app (`APPLE_BUNDLE_ID`, le
   * même que pour « Continuer avec Apple ») et, pour la production, son
   * identifiant numérique — *App Store Connect ▸ App Information ▸ Apple ID*.
   * Vide, les achats de production sont refusés et ceux du sandbox passent :
   * c'est l'état d'un serveur de développement.
   */
  APP_STORE_APP_APPLE_ID: optional(z.coerce.number().int().positive()),

  /**
   * Accepte les achats faits **dans Xcode**, avec le fichier `MemoBook.storekit`.
   *
   * 🚨 **Jamais en production.** Une transaction Xcode n'est signée par
   * personne : la bibliothèque d'Apple saute la vérification de signature pour
   * cet environnement, et n'importe qui pourrait s'en fabriquer une. Le serveur
   * refuse de démarrer si on l'active avec `NODE_ENV=production`.
   */
  APP_STORE_ALLOW_XCODE: z
    .enum(["true", "false"])
    .default("false")
    .transform((value) => value === "true"),

  /**
   * Les notifications — APNs, le service de notifications d'Apple. Voir
   * `services/apns.ts` et `docs/notifications.md`.
   *
   * Une **clé d'authentification** (`.p8`), créée une fois dans *Apple
   * Developer ▸ Certificates, IDs & Profiles ▸ Keys* en cochant « Apple Push
   * Notifications service ». Elle vaut pour le sandbox comme pour la
   * production, et ne se télécharge **qu'une fois** :
   * - `APNS_KEY_ID` — les dix caractères affichés à côté de la clé ;
   * - `APNS_TEAM_ID` — l'équipe, `HP2A94889S` (le même que `project.yml`) ;
   * - `APNS_PRIVATE_KEY` — le contenu du fichier `.p8`, en-têtes compris.
   *   Les retours à la ligne peuvent s'écrire `\n` : Railway garde mal une
   *   valeur sur plusieurs lignes.
   *
   * Vides, rien ne part : en développement les notifications sont
   * **journalisées** (titre, texte, lien) ; en production la tâche d'envoi ne
   * fait rien et le dit dans les logs — un serveur qui ne sait pas encore
   * notifier ne doit pas refuser de démarrer, ni marquer comme envoyé ce qui
   * n'est jamais parti.
   */
  APNS_KEY_ID: z.string().default(""),
  APNS_TEAM_ID: z.string().default(""),
  APNS_PRIVATE_KEY: z.string().default(""),
});

export type Env = z.infer<typeof schema> & {
  /** `true` quand le pipeline doit appeler les APIs externes pour de vrai. */
  live: boolean;

  /**
   * `true` quand Stripe encaisse de l'argent réel.
   *
   * Déduit du préfixe de la clé, jamais d'une variable à part : une variable
   * `STRIPE_MODE` pourrait mentir sur la clé posée à côté d'elle, le préfixe
   * non.
   */
  stripeLive: boolean;
};

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  // Charge `.env` quand on lit l'environnement réel. `process.loadEnvFile` est
  // natif depuis Node 20.12 : pas de `dotenv` à installer, et les variables
  // déjà posées dans l'environnement (Docker, CI, hébergeur) l'emportent.
  //
  // Un appelant qui fournit sa propre source — les tests — n'est pas concerné.
  if (source === process.env && existsSync(ENV_FILE)) {
    process.loadEnvFile(ENV_FILE);
  }

  const parsed = schema.safeParse(source);

  if (!parsed.success) {
    const details = parsed.error.issues
      .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
      .join("\n");
    throw new Error(
      `Configuration invalide. Vérifie ton .env (voir .env.example) :\n${details}`,
    );
  }

  const env = parsed.data;
  // Seule OpenAI décide de `live` : la transcription et la structuration n'ont
  // besoin que d'elle. Le PDF a sa propre clé et son propre axe (`RENDERER`) —
  // sans clé APITemplate, `auto` simule le rendu au lieu de simuler tout le
  // pipeline (Hugo, 01/10/2026 : tester le chat sans se soucier du PDF).
  const hasLiveKeys = env.OPENAI_API_KEY !== "";

  let live: boolean;
  switch (env.PIPELINE_MODE) {
    case "live":
      if (!hasLiveKeys) {
        throw new Error("PIPELINE_MODE=live mais OPENAI_API_KEY est vide.");
      }
      live = true;
      break;
    case "fake":
      live = false;
      break;
    default:
      live = hasLiveKeys;
  }

  if (env.RENDERER === "apitemplate" && env.APITEMPLATE_API_KEY === "") {
    throw new Error("RENDERER=apitemplate mais APITEMPLATE_API_KEY est vide.");
  }

  // Une clé secrète de test avec une clé publique de production — ou l'inverse
  // — est l'erreur de configuration la plus coûteuse qu'on puisse faire ici :
  // l'app monte une feuille de paiement sur un compte, le serveur encaisse sur
  // l'autre, et le paiement échoue *après* que l'utilisateur a validé Face ID.
  // Le préfixe le dit, donc on refuse de démarrer.
  const secretLive = env.STRIPE_SECRET_KEY.startsWith("sk_live_");
  const publishableLive = env.STRIPE_PUBLISHABLE_KEY.startsWith("pk_live_");

  if (env.STRIPE_SECRET_KEY !== "" && env.STRIPE_PUBLISHABLE_KEY !== "") {
    if (secretLive !== publishableLive) {
      throw new Error(
        "Les deux clés Stripe ne sont pas du même mode : " +
          `secrète=${secretLive ? "live" : "test"}, publique=${publishableLive ? "live" : "test"}. ` +
          "Reprends les deux sur le même écran du tableau de bord.",
      );
    }
  }

  // **En production, pas d'encaissement simulé.** Sans clé, le serveur
  // basculait sur le simulé : les commandes recevaient un secret factice, et le
  // webhook n'aurait vérifié aucune signature. Mieux vaut un déploiement qui
  // échoue qu'une API qui encaisse pour de faux (audit du 01/10/2026). La clé
  // secrète suffit ici — le worker n'a qu'elle, et n'a besoin que d'elle ; les
  // deux autres sont exigées par l'API seule, voir `assertApiPaymentsConfigured`.
  if (env.NODE_ENV === "production" && env.STRIPE_SECRET_KEY === "") {
    throw new Error(
      "Encaissement non configuré en production : STRIPE_SECRET_KEY est vide. " +
        "Voir docs/paiements.md § Configuration.",
    );
  }

  // Un achat Xcode n'est pas signé : l'accepter en production ouvrirait
  // l'abonnement à quiconque sait écrire un JSON. Voir `APP_STORE_ALLOW_XCODE`.
  if (env.APP_STORE_ALLOW_XCODE && env.NODE_ENV === "production") {
    throw new Error(
      "APP_STORE_ALLOW_XCODE=true en production : les achats Xcode ne sont pas signés. " +
        "Retire la variable du service.",
    );
  }

  return { ...env, live, stripeLive: secretLive };
}

/**
 * Ce que **l'API** exige de plus en production : la clé publique, que l'app
 * reçoit avec chaque paiement, et le secret du webhook, sans lequel aucune
 * commande ne sortirait de `draft`. Le worker ne sert ni l'un ni l'autre, et
 * ne les a pas sur Railway — d'où un contrôle à part, appelé par `server.ts`.
 */
export function assertApiPaymentsConfigured(env: Env): void {
  if (env.NODE_ENV !== "production") return;

  const missing = (["STRIPE_PUBLISHABLE_KEY", "STRIPE_WEBHOOK_SECRET"] as const).filter(
    (name) => env[name] === "",
  );
  if (missing.length > 0) {
    throw new Error(
      `Encaissement non configuré sur l'API : ${missing.join(", ")} vide(s). ` +
        "Voir docs/paiements.md § Configuration.",
    );
  }
}
