package com.memobook.core

/**
 * **Ce qu'un nom de fichier dit d'une photo** (T315, Hugo, 08/11/2026 — « les
 * métadonnées d'une photo ne doivent pas se perdre : lieu, date, heure. Une
 * photo venue de WhatsApp les a déjà perdues — ça se voit à son nom de
 * fichier : MemoBook doit le **détecter** et demander où et quand, faute de
 * quoi il la placera mal »). Jumeau de `PhotoFilename.swift`.
 *
 * ## Pourquoi le nom, et pas les métadonnées
 *
 * Parce qu'il ne reste que lui. Une messagerie réencode la photo et jette
 * l'EXIF au passage : plus de date de prise de vue, plus de position. Ce que
 * la photothèque garde alors est le jour où le fichier est **arrivé sur le
 * téléphone**, pas celui où la photo a été prise, et rien ne distingue les
 * deux. Le nom que WhatsApp donne à ses fichiers, lui, y survit.
 *
 * ⚠️ **Côté Android, la règle est là mais elle ne sert encore à rien** : la
 * conversation envoie des octets nus (`ChatModel.sendPhotos`), sans date ni
 * lieu par photo — la moitié client de T280 n'est pas portée. Ce fichier
 * attend son parcours de choix de photo, et il est ici pour que la règle
 * n'existe pas en deux versions le jour où il arrivera.
 */
object PhotoFilename {
    /** Les préfixes que WhatsApp pose sur ses propres fichiers. */
    private val kinds = setOf("img", "vid", "ptt", "aud", "doc")

    /**
     * Cette photo est passée par une messagerie : ses métadonnées sont
     * parties, et la date que la photothèque porte est celle de son arrivée.
     */
    fun isForwarded(name: String): Boolean {
        val base = name.lowercase()
        if (base.startsWith("whatsapp image") || base.startsWith("whatsapp video")) return true
        return hasWhatsAppCode(base)
    }

    /**
     * `img-20260811-wa0012.jpg` : un genre, huit chiffres de date, puis `wa`
     * et le numéro du fichier. WhatsApp sépare par un tiret, certaines
     * versions Android par un tiret bas.
     */
    private fun hasWhatsAppCode(base: String): Boolean {
        val parts = base.split('-', '_')
        if (parts.size < 3) return false
        if (parts[0] !in kinds) return false
        if (parts[1].length != 8 || !parts[1].all { it.isDigit() }) return false
        if (!parts[2].startsWith("wa")) return false
        // Le numéro s'arrête à l'extension : « wa0012.jpg » porte bien quatre
        // chiffres.
        return parts[2].drop(2).takeWhile { it.isDigit() }.length >= 4
    }
}
