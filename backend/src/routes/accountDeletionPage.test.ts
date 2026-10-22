import { describe, expect, it } from "vitest";
import { deletionRequestMailto, renderAccountDeletionPage } from "./accountDeletionPage.js";

describe("la page publique de suppression d'un compte", () => {
  const html = renderAccountDeletionPage("bonjour@memo-book.com");

  it("dit comment supprimer son compte depuis l'app", () => {
    expect(html).toContain("Supprimer mon compte");
    expect(html).toContain("sur iPhone ou sur Android");
  });

  it("propose un e-mail depuis l'adresse du compte, l'objet déjà posé", () => {
    expect(html).toContain("bonjour@memo-book.com");
    expect(deletionRequestMailto("bonjour@memo-book.com")).toMatch(
      /^mailto:bonjour@memo-book\.com\?subject=Supprimer%20mon%20compte%20MemoBook&body=/,
    );
  });

  it("dit ce qui part et ce qui reste", () => {
    expect(html).toContain("Ce qui est supprimé");
    expect(html).toContain("Ce qui est conservé");
  });

  it("échappe l'adresse", () => {
    expect(renderAccountDeletionPage('<b>"')).not.toContain('<b>"');
  });
});
