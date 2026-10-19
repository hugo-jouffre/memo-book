import { describe, expect, it } from "vitest";
import { appInviteUrl, appSiteAssociation, appStoreUrl, renderInvitePage } from "./invitePage.js";

describe("le lien d'invitation d'un co-voyageur", () => {
  it("déclare à Apple que l'app ouvre les liens /j/…", () => {
    const details = appSiteAssociation().applinks.details[0]!;
    expect(details.appIDs).toEqual(["HP2A94889S.com.memobook.app"]);
    expect(details.components[0]!["/"]).toBe("/j/*");
  });

  it("envoie un iPhone sans l'app sur l'App Store, et garde le code en clair", () => {
    const html = renderInvitePage("JHKFDA", appStoreUrl(6740000000));
    expect(html).toContain("https://apps.apple.com/app/id6740000000");
    expect(html).toContain("JHKFDA");
    expect(html).toContain(appInviteUrl("JHKFDA"));
  });

  it("cherche MemoBook sur l'App Store tant que l'identifiant n'est pas posé", () => {
    expect(appStoreUrl(undefined)).toContain("search?term=MemoBook");
  });

  it("échappe ce qu'on lui passe", () => {
    expect(renderInvitePage('<script>"', appStoreUrl(undefined))).not.toContain('<script>"');
  });
});
