import { describe, expect, it } from "vitest";
import {
  androidAssetLinks,
  androidIntentUrl,
  appInviteUrl,
  appSiteAssociation,
  appStoreUrl,
  inviteHost,
  inviteUrlOf,
  playStoreUrl,
  renderInvitePage,
} from "./invitePage.js";

const iosOnly = (appleId?: number) => ({ appStore: appStoreUrl(appleId), playStore: null });

describe("le lien d'invitation d'un co-voyageur", () => {
  it("déclare à Apple que l'app ouvre les liens /j/…", () => {
    const details = appSiteAssociation().applinks.details[0]!;
    expect(details.appIDs).toEqual(["HP2A94889S.com.memobook.app"]);
    expect(details.components[0]!["/"]).toBe("/j/*");
  });

  it("envoie un iPhone sans l'app sur l'App Store, et garde le code en clair", () => {
    const html = renderInvitePage("JHKFDA", iosOnly(6740000000));
    expect(html).toContain("https://apps.apple.com/app/id6740000000");
    expect(html).toContain("JHKFDA");
    expect(html).toContain(appInviteUrl("JHKFDA"));
  });

  it("cherche MemoBook sur l'App Store tant que l'identifiant n'est pas posé", () => {
    expect(appStoreUrl(undefined)).toContain("search?term=MemoBook");
  });

  it("échappe ce qu'on lui passe", () => {
    expect(renderInvitePage('<script>"', iosOnly())).not.toContain('<script>"');
  });

  it("ne promet pas l'app Android tant qu'elle n'est pas sur le Play Store", () => {
    const html = renderInvitePage("JHKFDA", iosOnly());
    expect(html).toContain("MemoBook est une app pour iPhone.");
    expect(html).not.toContain("play.google.com");
  });

  it("envoie un téléphone Android sur le Play Store une fois l'app publiée", () => {
    const html = renderInvitePage("JHKFDA", { appStore: appStoreUrl(undefined), playStore: playStoreUrl() });
    expect(html).toContain("https://play.google.com/store/apps/details?id=com.memobook.app");
    expect(html).toContain("MemoBook est une app pour iPhone et Android.");
  });

  it("ouvre l'app Android depuis Chrome par un intent://", () => {
    const html = renderInvitePage("JHKFDA", iosOnly());
    expect(html).toContain(androidIntentUrl("join?code=JHKFDA"));
    expect(androidIntentUrl("join?code=JHKFDA")).toBe(
      "intent://join?code=JHKFDA#Intent;scheme=memobook;package=com.memobook.app;end",
    );
  });
});

/**
 * **Le beau lien** (Hugo, 10/11/2026) — « on devrait maintenant avoir un beau
 * lien comme join.memo-book.com ».
 */
describe("le domaine des invitations", () => {
  const sans = { INVITE_PUBLIC_BASE_URL: "", API_PUBLIC_BASE_URL: "https://api.test", RAILWAY_PUBLIC_DOMAIN: "", APP_LINK_BASE_URL: "" };
  const avec = { ...sans, INVITE_PUBLIC_BASE_URL: "https://join.memo-book.com" };

  it("pose le code à la racine du domaine", () => {
    expect(inviteUrlOf(avec, "JHKFDA")).toBe("https://join.memo-book.com/JHKFDA");
  });

  it("garde l'ancienne adresse tant qu'aucun domaine n'est posé", () => {
    expect(inviteUrlOf(sans, "JHKFDA")).toBe("https://api.test/j/JHKFDA");
  });

  it("supporte un domaine écrit sans protocole, ou avec une barre finale", () => {
    expect(inviteUrlOf({ ...sans, INVITE_PUBLIC_BASE_URL: "join.memo-book.com" }, "JHKFDA")).toBe(
      "https://join.memo-book.com/JHKFDA",
    );
    expect(inviteUrlOf({ ...sans, INVITE_PUBLIC_BASE_URL: "https://join.memo-book.com/" }, "JHKFDA")).toBe(
      "https://join.memo-book.com/JHKFDA",
    );
  });

  it("lit l'hôte, et se tait sur une valeur illisible", () => {
    expect(inviteHost(avec)).toBe("join.memo-book.com");
    expect(inviteHost({ INVITE_PUBLIC_BASE_URL: "" })).toBeNull();
    expect(inviteHost({ INVITE_PUBLIC_BASE_URL: "pas une adresse du tout" })).toBeNull();
  });

  /**
   * ⚠️ Le motif **dépend de l'hôte**. Un `/*` servi par l'API ferait ouvrir
   * l'app sur `/c/<jeton>`, l'aperçu public d'un carnet, et sur la page du mot
   * de passe oublié.
   */
  it("ne revendique tout le domaine que sur celui des invitations", () => {
    expect(appSiteAssociation(true).applinks.details[0]!.components[0]!["/"]).toBe("/*");
    expect(appSiteAssociation(false).applinks.details[0]!.components[0]!["/"]).toBe("/j/*");
  });
});

describe("les App Links d'Android", () => {
  it("déclare com.memobook.app avec les empreintes de ses certificats", () => {
    const [statement] = androidAssetLinks(["34:77:18:AD"]);
    expect(statement!.relation).toEqual(["delegate_permission/common.handle_all_urls"]);
    expect(statement!.target).toEqual({
      namespace: "android_app",
      package_name: "com.memobook.app",
      sha256_cert_fingerprints: ["34:77:18:AD"],
    });
  });

  it("ne déclare rien sans empreinte", () => {
    expect(androidAssetLinks([])).toEqual([]);
  });
});
