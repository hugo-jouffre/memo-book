package com.memobook.networking

import java.io.ByteArrayOutputStream
import java.util.UUID

/**
 * Construction d'un corps `multipart/form-data`. Le jumeau de
 * `MemoBookNetworking/MultipartFormData.swift`, écrit à la main plutôt que
 * par le `MultipartBody` d'OkHttp : le corps part octet pour octet comme celui
 * d'iOS, et la frontière se lit dans la trace.
 *
 * Le back-end lit le fichier via `@fastify/multipart` et les champs texte à
 * côté : l'ordre importe peu, mais le fichier doit porter le nom `file`.
 */
internal class MultipartFormData(
    val boundary: String = "memobook-${UUID.randomUUID().toString().uppercase()}",
) {
    private val body = ByteArrayOutputStream()

    val contentType: String get() = "multipart/form-data; boundary=$boundary"

    fun addField(name: String, value: String) {
        append("--$boundary\r\n")
        append("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
        append("$value\r\n")
    }

    fun addFile(name: String, filename: String, mimeType: String, data: ByteArray) {
        append("--$boundary\r\n")
        append("Content-Disposition: form-data; name=\"$name\"; filename=\"$filename\"\r\n")
        append("Content-Type: $mimeType\r\n\r\n")
        body.write(data)
        append("\r\n")
    }

    /** Renvoie le corps complet, terminé par sa frontière de fermeture. */
    fun finalized(): ByteArray = body.toByteArray() + "--$boundary--\r\n".toByteArray(Charsets.UTF_8)

    private fun append(string: String) {
        // Le corps est composé d'en-têtes ASCII et de binaire : l'UTF-8 ne
        // change rien aux premiers, et laisse passer un nom de lieu accentué.
        body.write(string.toByteArray(Charsets.UTF_8))
    }
}
