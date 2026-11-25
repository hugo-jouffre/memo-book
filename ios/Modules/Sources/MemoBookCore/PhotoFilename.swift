import Foundation

/**
 **Ce qu'un nom de fichier dit d'une photo** (T315, Hugo, 08/11/2026 — « les
 métadonnées d'une photo ne doivent pas se perdre : lieu, date, heure. Une
 photo venue de WhatsApp les a déjà perdues — ça se voit à son nom de
 fichier : MemoBook doit le **détecter** et demander où et quand, faute de quoi
 il la placera mal »).

 ## Pourquoi le nom, et pas les métadonnées

 Parce qu'il ne reste que lui. Une messagerie réencode la photo et jette
 l'EXIF au passage : plus de date de prise de vue, plus de position. Ce que la
 photothèque garde alors — `PHAsset.creationDate` — est le jour où le fichier
 est **arrivé sur le téléphone**, pas celui où la photo a été prise, et rien
 dans la fiche ne distingue les deux. Le carnet range donc la photo au jour où
 on l'a reçue : une photo que Fanny envoie une semaine plus tard tombe une
 semaine trop loin.

 Le nom que WhatsApp donne à ses fichiers, lui, survit à l'enregistrement dans
 la photothèque. C'est le seul témoin, et c'est celui que Hugo a vu.

 ## Les deux formes, et rien d'autre

 - `IMG-20260811-WA0012.jpg` — ce que l'app pose sur un fichier reçu ;
 - `WhatsApp Image 2026-08-11 at 12.34.56.jpeg` — ce que la version de bureau
   et les exports de conversation posent.

 ⚠️ **Les autres messageries ne se détectent pas, et c'est délibéré.** Telegram
 enregistre `IMG_20260811_123456.jpg`, qui est aussi le nom d'un appareil photo
 Android : prendre cette forme ferait poser la question à des photos qui
 portent très bien leur date. Une question de trop sur une photo saine coûte
 plus cher qu'une photo mal rangée de plus — on ne la pose que quand on est
 sûr. La liste s'allongera le jour où une autre app laissera une trace aussi
 nette.
 */
public enum PhotoFilename {
    /// Les préfixes que WhatsApp pose sur ses propres fichiers.
    private static let kinds = ["img", "vid", "ptt", "aud", "doc"]

    /// Cette photo est passée par une messagerie : ses métadonnées sont
    /// parties, et la date que la photothèque porte est celle de son arrivée.
    public static func isForwarded(_ name: String) -> Bool {
        let base = name.lowercased()
        if base.hasPrefix("whatsapp image") || base.hasPrefix("whatsapp video") { return true }
        return hasWhatsAppCode(base)
    }

    /// `img-20260811-wa0012.jpg` : un genre, huit chiffres de date, puis `wa`
    /// et le numéro du fichier. WhatsApp sépare par un tiret, certaines
    /// versions Android par un tiret bas.
    private static func hasWhatsAppCode(_ base: String) -> Bool {
        let parts = base.split { $0 == "-" || $0 == "_" }
        guard parts.count >= 3,
            kinds.contains(String(parts[0])),
            parts[1].count == 8,
            parts[1].allSatisfy(\.isNumber),
            parts[2].hasPrefix("wa")
        else { return false }
        // Le numéro s'arrête à l'extension : « wa0012.jpg » porte bien quatre
        // chiffres.
        return parts[2].dropFirst(2).prefix(while: \.isNumber).count >= 4
    }
}
