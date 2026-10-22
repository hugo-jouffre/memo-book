package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonUnquotedLiteral
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigDecimal
import java.net.URI
import java.net.URISyntaxException
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.ZoneOffset

// Le décodage accordé au back-end MemoBook. Le jumeau de `MemoBookCore/Coding.swift`.

/**
 * Le JSON du back-end, lu et écrit comme sur iOS.
 *
 * - `ignoreUnknownKeys` : un champ ajouté côté serveur ne casse pas une version
 *   déjà installée — `Codable` l'ignore aussi.
 * - `explicitNulls = false` : un champ optionnel absent vaut `null`, et un
 *   `null` n'est pas écrit — `encodeIfPresent` d'iOS.
 * - `coerceInputValues` reste **éteint** : un champ obligatoire qui arrive
 *   `null` est une erreur de décodage, comme sur iOS.
 */
val MemoBookJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}

/**
 * Une date du serveur. Elles arrivent au format `toISOString()` de JavaScript,
 * avec les millisecondes (`2026-08-08T12:48:25.295Z`), parfois sans : les deux
 * se lisent ; on écrit toujours avec.
 */
object MemoBookDate {
    fun parse(raw: String): Instant? = try {
        Instant.from(DateTimeFormatter.ISO_OFFSET_DATE_TIME.parse(raw))
    } catch (_: DateTimeParseException) {
        null
    }

    /** Toujours avec les millisecondes, comme `.withFractionalSeconds` d'iOS. */
    fun format(instant: Instant): String = WITH_MILLISECONDS.format(instant)

    private val WITH_MILLISECONDS: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)
}

/** `Date` de Swift ↔ `Instant` : à poser sur chaque champ daté (`@Serializable(with = InstantSerializer::class)`). */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.memobook.core.Instant", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): Instant {
        val raw = decoder.decodeString()
        return MemoBookDate.parse(raw) ?: throw SerializationException("Date ISO 8601 illisible : $raw")
    }

    override fun serialize(encoder: Encoder, value: Instant) {
        encoder.encodeString(MemoBookDate.format(value))
    }
}

/**
 * Le patron des énumérations du serveur **qui tolèrent l'inconnu** : une valeur
 * ajoutée côté serveur ne fait pas planter une version installée (le
 * `case unknown(String)` d'iOS). L'énumération Kotlin est une `sealed interface`
 * avec un cas `Unknown(raw)` ; son sérialiseur hérite de celui-ci.
 */
abstract class RawValueSerializer<T>(
    serialName: String,
    private val rawValue: (T) -> String,
    private val fromRaw: (String) -> T,
) : KSerializer<T> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor(serialName, PrimitiveKind.STRING)
    override fun deserialize(decoder: Decoder): T = fromRaw(decoder.decodeString())
    override fun serialize(encoder: Encoder, value: T) = encoder.encodeString(rawValue(value))
}

/**
 * `URL` de Swift ↔ `URI` : à poser sur chaque champ `URL` du Swift
 * (`@Serializable(with = UriSerializer::class)`). Comme `URL(string:)`, une
 * adresse illisible est une erreur de décodage, pas une valeur vide.
 */
object UriSerializer : KSerializer<URI> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.memobook.core.URI", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): URI {
        val raw = decoder.decodeString()
        return try {
            URI(raw)
        } catch (_: URISyntaxException) {
            throw SerializationException("Adresse illisible : $raw")
        }
    }

    override fun serialize(encoder: Encoder, value: URI) {
        encoder.encodeString(value.toString())
    }
}

/**
 * `Decimal` de Swift ↔ `BigDecimal` : un montant arrive en **nombre** JSON
 * (`12.9`), et le passer par un `Double` le ferait mentir d'un centime. Le
 * texte du nombre est lu tel quel, et réécrit tel quel.
 */
object BigDecimalSerializer : KSerializer<BigDecimal> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.memobook.core.BigDecimal", PrimitiveKind.DOUBLE)

    override fun deserialize(decoder: Decoder): BigDecimal {
        val raw = if (decoder is JsonDecoder) {
            decoder.decodeJsonElement().jsonPrimitive.content
        } else {
            decoder.decodeString()
        }
        return raw.toBigDecimalOrNull() ?: throw SerializationException("Montant illisible : $raw")
    }

    override fun serialize(encoder: Encoder, value: BigDecimal) {
        if (encoder is JsonEncoder) {
            encoder.encodeJsonElement(JsonUnquotedLiteral(value.toPlainString()))
        } else {
            encoder.encodeString(value.toPlainString())
        }
    }
}
