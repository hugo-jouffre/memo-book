import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { hashSessionToken } from "../src/lib/auth.js";
import { hashPassword, verifyPassword } from "../src/lib/password.js";
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

let harness: TestHarness;

async function boot(verifier: SocialVerifier = fakeVerifier()): Promise<TestHarness> {
  if (harness) await harness.close();
  harness = await createHarness({ socialVerifier: verifier });
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
