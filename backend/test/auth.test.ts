import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { hashSessionToken } from "../src/lib/auth.js";
import { hashPassword, verifyPassword } from "../src/lib/password.js";
import { passwordResetUrl, type Mailer, type PasswordResetMail } from "../src/services/mailer.js";
import type { SocialVerifier, VerifiedIdentity } from "../src/services/socialIdentity.js";
import { createHarness, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * L'entrée dans un compte, de bout en bout.
 *
 * Le vérificateur de jetons est simulé : appeler Apple et Google pour de vrai
 * exigerait des jetons signés par eux, donc une identité réelle et un réseau.
 * Ce qui est vérifié ici, c'est tout ce qui vient **après** la vérification —
 * la création du compte, le rattachement des identités, les sessions. La
 * vérification cryptographique elle-même appartient à `jose`.
 */
function fakeVerifier(identity: Partial<VerifiedIdentity> = {}): SocialVerifier {
  const build = (provider: VerifiedIdentity["provider"]): VerifiedIdentity => ({
    provider,
    subject: `${provider}-sub`,
    email: `hugo@memobook.app`,
    emailVerified: true,
    ...identity,
  });

  return {
    verifyApple: async () => build("apple"),
    verifyGoogle: async () => build("google"),
  };
}

/** Un expéditeur qui garde ce qu'il aurait envoyé, pour le lire dans le test. */
function fakeMailer(): Mailer & { sent: PasswordResetMail[] } {
  const sent: PasswordResetMail[] = [];
  return {
    sent,
    async sendPasswordReset(message) {
      sent.push(message);
    },
  };
}

let harness: TestHarness;
let mailer = fakeMailer();

async function boot(verifier: SocialVerifier = fakeVerifier()): Promise<TestHarness> {
  if (harness) await harness.close();
  mailer = fakeMailer();
  harness = await createHarness({ socialVerifier: verifier, mailer });
  await resetDatabase(harness.prisma);
  return harness;
}

afterAll(async () => {
  await harness?.close();
});

describe("mot de passe", () => {
  it("se vérifie contre sa propre empreinte, et pas contre une autre", async () => {
    const stored = await hashPassword("carnet2026");
    expect(await verifyPassword("carnet2026", stored)).toBe(true);
    expect(await verifyPassword("carnet2027", stored)).toBe(false);
  });

  it("donne deux empreintes différentes pour le même mot de passe", async () => {
    // Le sel est tiré à chaque fois : deux comptes avec le même mot de passe ne
    // doivent pas être reconnaissables en lisant la base.
    const a = await hashPassword("carnet2026");
    const b = await hashPassword("carnet2026");
    expect(a).not.toBe(b);
  });

  it("refuse une empreinte illisible sans lever", async () => {
    expect(await verifyPassword("carnet2026", "n'importe quoi")).toBe(false);
  });
});

describe("inscription et connexion par mot de passe", () => {
  beforeEach(async () => {
    await boot();
  });

  it("crée le compte et ouvre une session", async () => {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signup",
      payload: {
        email: "Hugo@MemoBook.app",
        password: "carnet2026",
        firstName: "Hugo",
      },
    });

    expect(response.statusCode).toBe(201);
    const body = response.json<{ token: string; account: { email: string } }>();
    // L'adresse est normalisée : « Hugo@MemoBook.app » et « hugo@memobook.app »
    // sont la même personne.
    expect(body.account.email).toBe("hugo@memobook.app");

    const session = await harness.prisma.session.findUnique({
      where: { tokenHash: hashSessionToken(body.token) },
    });
    expect(session).not.toBeNull();
  });

  it("offre trois étapes à tout compte qui s'ouvre", async () => {
    // Par mot de passe…
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signup",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });
    const byPassword = await harness.prisma.account.findUniqueOrThrow({
      where: { email: "hugo@memobook.app" },
    });
    expect(byPassword.offeredSteps).toBe(3);
    expect(byPassword.remainingSteps).toBe(3);

    // … comme par un fournisseur : c'est l'ouverture du compte qui offre les
    // étapes, pas la façon d'entrer.
    await boot(fakeVerifier({ email: "clara@memobook.app" }));
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/google",
      payload: { identityToken: "google-token" },
    });
    const bySocial = await harness.prisma.account.findUniqueOrThrow({
      where: { email: "clara@memobook.app" },
    });
    expect(bySocial.offeredSteps).toBe(3);
    expect(bySocial.remainingSteps).toBe(3);
  });

  it("ne stocke jamais le mot de passe en clair", async () => {
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signup",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });

    const account = await harness.prisma.account.findUniqueOrThrow({
      where: { email: "hugo@memobook.app" },
    });
    expect(account.passwordHash).not.toContain("carnet2026");
    expect(account.passwordHash).toMatch(/^scrypt\$/);
  });

  it("refuse une seconde inscription sur la même adresse", async () => {
    const payload = { email: "hugo@memobook.app", password: "carnet2026" };
    await harness.app.inject({ method: "POST", url: "/v1/auth/signup", payload });
    const second = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signup",
      payload,
    });

    expect(second.statusCode).toBe(409);
  });

  it("applique les mêmes règles de mot de passe que l'app", async () => {
    for (const password of ["court1", "sanschiffre", "12345678"]) {
      const response = await harness.app.inject({
        method: "POST",
        url: "/v1/auth/signup",
        payload: { email: `${password}@memobook.app`, password },
      });
      expect(response.statusCode, password).toBe(400);
    }
  });

  it("dit la même chose pour une adresse inconnue et un mot de passe faux", async () => {
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signup",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });

    const wrongPassword = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      payload: { email: "hugo@memobook.app", password: "carnet2027" },
    });
    const unknownEmail = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      payload: { email: "personne@memobook.app", password: "carnet2026" },
    });

    expect(wrongPassword.statusCode).toBe(401);
    expect(unknownEmail.statusCode).toBe(401);
    // Sans ça, la route devient un moyen de savoir qui a un compte.
    expect(unknownEmail.json()).toEqual(wrongPassword.json());
  });

  it("connecte avec les bons identifiants", async () => {
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signup",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });

    expect(response.statusCode).toBe(200);
    expect(response.json<{ token: string }>().token).toBeTruthy();
  });
});

describe("mot de passe oublié", () => {
  beforeEach(async () => {
    await boot();
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signup",
      payload: { email: "hugo@memobook.app", password: "carnet2026", firstName: "Hugo" },
    });
  });

  it("envoie un secret, et n'en garde que l'empreinte", async () => {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/forgot",
      payload: { email: "Hugo@MemoBook.app" },
    });

    expect(response.statusCode).toBe(202);
    expect(mailer.sent).toHaveLength(1);
    const [mail] = mailer.sent;
    expect(mail?.to).toBe("hugo@memobook.app");
    expect(mail?.firstName).toBe("Hugo");

    const resets = await harness.prisma.passwordReset.findMany();
    expect(resets).toHaveLength(1);
    expect(resets[0]?.tokenHash).toBe(hashSessionToken(mail!.token));
    expect(resets[0]?.tokenHash).not.toBe(mail!.token);
    expect(resets[0]?.expiresAt.getTime()).toBeGreaterThan(Date.now());
  });

  it("dit qu'une adresse inconnue n'a pas de compte, sans rien envoyer", async () => {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/forgot",
      payload: { email: "Personne@MemoBook.app" },
    });

    expect(response.statusCode).toBe(404);
    const body = response.json<{ error: string; message: string }>();
    expect(body.error).toBe("unknown_account");
    // L'adresse est reprise **normalisée** dans la phrase : c'est celle que
    // l'app affiche en rouge, et elle doit être celle qu'on a cherchée.
    expect(body.message).toContain("personne@memobook.app");
    expect(mailer.sent).toHaveLength(0);
    expect(await harness.prisma.passwordReset.count()).toBe(0);
  });

  it("ne garde qu'un secret valable : le dernier envoyé", async () => {
    for (let i = 0; i < 2; i += 1) {
      await harness.app.inject({
        method: "POST",
        url: "/v1/auth/password/forgot",
        payload: { email: "hugo@memobook.app" },
      });
    }

    expect(mailer.sent).toHaveLength(2);
    const resets = await harness.prisma.passwordReset.findMany();
    expect(resets).toHaveLength(1);
    expect(resets[0]?.tokenHash).toBe(hashSessionToken(mailer.sent[1]!.token));
  });

  it("refuse une adresse mal formée", async () => {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/forgot",
      payload: { email: "pas-une-adresse" },
    });

    expect(response.statusCode).toBe(400);
    expect(mailer.sent).toHaveLength(0);
  });

  it("écrit un lien qui ouvre l'app, avec le secret dedans", () => {
    const url = passwordResetUrl(harness.context.env, "a+b/c");
    expect(url).toBe("memobook://password/reset?token=a%2Bb%2Fc");

    // Le jour du lien universel, le même chemin derrière un domaine.
    const universal = passwordResetUrl(
      { ...harness.context.env, APP_LINK_BASE_URL: "https://memo-book.com/app/" },
      "t",
    );
    expect(universal).toBe("https://memo-book.com/app/password/reset?token=t");
  });

  async function requestReset(): Promise<string> {
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/forgot",
      payload: { email: "hugo@memobook.app" },
    });
    return mailer.sent.at(-1)!.token;
  }

  it("change le mot de passe, ouvre une session, et ferme les autres", async () => {
    const before = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });
    const oldAuthorization = `Bearer ${before.json<{ token: string }>().token}`;

    const token = await requestReset();
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/reset",
      payload: { token, password: "nouveau2027" },
    });

    expect(response.statusCode).toBe(200);
    const body = response.json<{ token: string; account: { email: string } }>();
    expect(body.account.email).toBe("hugo@memobook.app");

    // La session neuve marche, l'ancienne est dehors.
    const me = await harness.app.inject({
      method: "GET",
      url: "/v1/auth/me",
      headers: { authorization: `Bearer ${body.token}` },
    });
    expect(me.statusCode).toBe(200);
    const old = await harness.app.inject({
      method: "GET",
      url: "/v1/auth/me",
      headers: { authorization: oldAuthorization },
    });
    expect(old.statusCode).toBe(401);

    // Le nouveau mot de passe ouvre, l'ancien ne peut plus.
    const withNew = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      payload: { email: "hugo@memobook.app", password: "nouveau2027" },
    });
    expect(withNew.statusCode).toBe(200);
    const withOld = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });
    expect(withOld.statusCode).toBe(401);

    // Ouvrir le lien a prouvé qu'on lit la boîte.
    const account = await harness.prisma.account.findUniqueOrThrow({
      where: { email: "hugo@memobook.app" },
    });
    expect(account.emailVerifiedAt).not.toBeNull();
  });

  it("ne sert qu'une fois", async () => {
    const token = await requestReset();
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/reset",
      payload: { token, password: "nouveau2027" },
    });
    const again = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/reset",
      payload: { token, password: "encore2028" },
    });

    expect(again.statusCode).toBe(400);
    expect(again.json<{ error: string }>().error).toBe("invalid_reset_token");
  });

  it("refuse un secret expiré ou inventé", async () => {
    const token = await requestReset();
    await harness.prisma.passwordReset.updateMany({
      data: { expiresAt: new Date(Date.now() - 1_000) },
    });

    const expired = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/reset",
      payload: { token, password: "nouveau2027" },
    });
    expect(expired.statusCode).toBe(400);

    const invented = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/reset",
      payload: { token: "n-importe-quoi", password: "nouveau2027" },
    });
    expect(invented.statusCode).toBe(400);
    expect(invented.json<{ error: string }>().error).toBe("invalid_reset_token");
  });

  it("applique la règle du mot de passe au nouveau", async () => {
    const token = await requestReset();
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/reset",
      payload: { token, password: "court" },
    });

    expect(response.statusCode).toBe(400);
    // Le secret n'est pas consommé par un essai refusé : on corrige et on
    // renvoie, sans redemander un e-mail.
    const retry = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/password/reset",
      payload: { token, password: "nouveau2027" },
    });
    expect(retry.statusCode).toBe(200);
  });
});

describe("entrée par un fournisseur tiers", () => {
  it("crée un compte, puis retrouve le même à la reconnexion", async () => {
    await boot();

    const first = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      payload: { identityToken: "peu-importe", nonce: "nonce", firstName: "Hugo" },
    });
    const second = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      payload: { identityToken: "peu-importe", nonce: "nonce" },
    });

    expect(first.statusCode).toBe(200);
    const a = first.json<{ account: { id: string } }>().account;
    const b = second.json<{ account: { id: string; firstName: string } }>().account;
    expect(b.id).toBe(a.id);
    // Apple ne redonne pas le nom à la deuxième autorisation : c'est le compte
    // qui doit l'avoir gardé.
    expect(b.firstName).toBe("Hugo");
    expect(await harness.prisma.account.count()).toBe(1);
  });

  it("rattache Google au compte Apple quand l'adresse est certifiée", async () => {
    await boot();

    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      payload: { identityToken: "t", nonce: "n" },
    });
    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/google",
      payload: { identityToken: "t" },
    });

    expect(await harness.prisma.account.count()).toBe(1);
    expect(await harness.prisma.identity.count()).toBe(2);
  });

  it("n'ouvre pas un compte existant sur une adresse non certifiée", async () => {
    // Le scénario qu'on refuse : quelqu'un déclare l'adresse d'autrui chez un
    // fournisseur qui ne la vérifie pas, et hériterait de son compte.
    await boot(fakeVerifier({ emailVerified: false }));

    const apple = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      payload: { identityToken: "t", nonce: "n" },
    });
    const google = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/google",
      payload: { identityToken: "t" },
    });

    // Les statuts comptent autant que le décompte : sans eux, une erreur 500
    // ressemblerait à un rattachement refusé, ce qui est le résultat attendu.
    expect(apple.statusCode).toBe(200);
    expect(google.statusCode).toBe(200);
    expect(await harness.prisma.account.count()).toBe(2);
  });

  it("ne pose pas une adresse non certifiée sur le compte", async () => {
    // Elle reste sur l'identité : le compte, lui, n'a pas d'adresse tant que
    // personne ne l'a prouvée. C'est ce qui garde la contrainte d'unicité
    // utilisable pour deux personnes qui déclareraient la même.
    await boot(fakeVerifier({ emailVerified: false }));

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      payload: { identityToken: "t", nonce: "n" },
    });

    expect(response.json<{ account: { email: string | null } }>().account.email).toBeNull();

    const identity = await harness.prisma.identity.findFirstOrThrow();
    expect(identity.email).toBe("hugo@memobook.app");
  });

  it("accepte une identité sans adresse du tout", async () => {
    // Apple avec l'adresse masquée et le partage refusé.
    await boot(fakeVerifier({ email: null, emailVerified: false }));

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/apple",
      payload: { identityToken: "t", nonce: "n" },
    });

    expect(response.statusCode).toBe(200);
    expect(response.json<{ account: { email: string | null } }>().account.email).toBeNull();
  });
});

describe("session", () => {
  beforeEach(async () => {
    await boot();
  });

  async function openSession(): Promise<string> {
    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signup",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });
    return `Bearer ${response.json<{ token: string }>().token}`;
  }

  it("donne accès au compte, et rien sans token", async () => {
    const authorization = await openSession();

    const withToken = await harness.app.inject({
      method: "GET",
      url: "/v1/auth/me",
      headers: { authorization },
    });
    const without = await harness.app.inject({ method: "GET", url: "/v1/auth/me" });

    expect(withToken.statusCode).toBe(200);
    expect(without.statusCode).toBe(401);
  });

  it("refuse une session expirée et la supprime", async () => {
    const authorization = await openSession();
    await harness.prisma.session.updateMany({
      data: { expiresAt: new Date(Date.now() - 1000) },
    });

    const response = await harness.app.inject({
      method: "GET",
      url: "/v1/auth/me",
      headers: { authorization },
    });

    expect(response.statusCode).toBe(401);
    expect(await harness.prisma.session.count()).toBe(0);
  });

  it("ne ferme que la session présentée", async () => {
    const phone = await openSession();
    const tablet = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      payload: { email: "hugo@memobook.app", password: "carnet2026" },
    });
    const tabletAuth = `Bearer ${tablet.json<{ token: string }>().token}`;

    await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signout",
      headers: { authorization: phone },
    });

    const phoneAfter = await harness.app.inject({
      method: "GET",
      url: "/v1/auth/me",
      headers: { authorization: phone },
    });
    const tabletAfter = await harness.app.inject({
      method: "GET",
      url: "/v1/auth/me",
      headers: { authorization: tabletAuth },
    });

    expect(phoneAfter.statusCode).toBe(401);
    expect(tabletAfter.statusCode).toBe(200);
  });
});
