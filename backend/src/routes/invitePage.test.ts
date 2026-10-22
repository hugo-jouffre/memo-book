import { describe, expect, it } from "vitest";
import {
  androidAssetLinks,
  androidIntentUrl,
  appInviteUrl,
  appSiteAssociation,
  appStoreUrl,
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
