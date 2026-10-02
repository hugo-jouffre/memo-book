/** Échappe le texte destiné à un fragment HTML simple (`<p>`, `<br>`, `<b>`). */
export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
