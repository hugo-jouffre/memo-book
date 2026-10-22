package com.memobook.core

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Le **crédit du jour**, côté app : ce qui reste, les phases de la barre
 * d'enregistrement, le coût d'un texte, et les phrases qui le disent. Mêmes cas
 * que `DailyCreditTests.swift`.
 *
 * Le serveur tranche (`services/dailyCredit.ts`) ; ici on ne teste que ce que
 * l'app en déduit pour prévenir — à 4:30, à 4:55, à 5:00 — et ce qu'elle
 * affiche dans les réglages du voyage.
 */
class DailyCreditTest {
    /**
     * Un crédit du catalogue (5 min, 75 ms par caractère) dont il reste
     * `remaining` millisecondes.
     */
    private fun credit(remaining: Int, isUnlimited: Boolean = false): DailyCredit =
        DailyCredit(isUnlimited = isUnlimited, usedMs = DailyCredit.Catalog.limitMs - remaining)

    private fun decode(json: String): DailyCredit = MemoBookJson.decodeFromString(DailyCredit.serializer(), json)

    // MARK: - Ce qui reste

    @Test
    fun remainingNeverGoesNegative() {
        // Un vocal accepté dans la tolérance (3 s) peut faire dépasser : la
        // ligne doit lire « Plus rien », pas « -2 s ».
        val credit = DailyCredit(usedMs = 303_000)
        assertEquals(0, credit.remainingMs)
        assertEquals(1.0, credit.fraction)
        assertTrue(credit.isExhausted)
    }

    @Test
    fun fractionIsWhatTheTripHasAlreadyTold() {
        val credit = DailyCredit(usedMs = 100_000)
        assertEquals(200_000, credit.remainingMs)
        assertEquals(1.0 / 3.0, credit.fraction, absoluteTolerance = 0.0001)
        assertFalse(credit.isExhausted)
    }

    @Test
    fun zeroLimitDoesNotDivideByZero() {
        val credit = DailyCredit(limitMs = 0, usedMs = 10)
        assertEquals(1.0, credit.fraction)
        assertEquals(0, credit.remainingMs)
    }

    @Test
    fun aSubscriberIsNeverExhausted() {
        // Il ne consomme rien du pot commun, même quand ses co-voyageurs l'ont
        // vidé : le crédit lu par un abonné dit « illimité », pas « épuisé ».
        val credit = DailyCredit(isUnlimited = true, usedMs = DailyCredit.Catalog.limitMs)
        assertFalse(credit.isExhausted)
        assertEquals(DailyCredit.Phase.Calm, credit.phase)
        assertTrue(credit.allows(text = "a".repeat(10_000)))
    }

    // MARK: - Pendant l'enregistrement

    @Test
    fun remainingWhileRecordingCountsWhatIsBeingSaid() {
        val credit = credit(remaining = 180_000)
        assertEquals(120_000, credit.remainingMs(whileRecording = 60_000))
        assertEquals(0, credit.remainingMs(whileRecording = 200_000))
        // Une horloge qui recule (un `currentTime` relu trop tôt) ne rend
        // jamais du crédit.
        assertEquals(180_000, credit.remainingMs(whileRecording = -5_000))
    }

    @Test
    fun phasesFollowTheServedThresholds() {
        val full = credit(remaining = 300_000)
        assertEquals(DailyCredit.Phase.Calm, full.phase(remainingMs = 30_001))
        assertEquals(DailyCredit.Phase.Warning, full.phase(remainingMs = 30_000))
        assertEquals(DailyCredit.Phase.Warning, full.phase(remainingMs = 5_001))
        assertEquals(DailyCredit.Phase.Urgent, full.phase(remainingMs = 5_000))
        assertEquals(DailyCredit.Phase.Urgent, full.phase(remainingMs = 1))
        assertEquals(DailyCredit.Phase.Exhausted, full.phase(remainingMs = 0))
    }

    @Test
    fun thresholdsTravelWithTheBalance() {
        // Si le serveur avance l'avertissement à une minute, l'app suit : les
        // seuils ne sont pas écrits dans la barre d'enregistrement.
        val credit = DailyCredit(usedMs = 0, warningRemainingMs = 60_000, urgentRemainingMs = 10_000)
        assertEquals(DailyCredit.Phase.Warning, credit.phase(remainingMs = 45_000))
        assertEquals(DailyCredit.Phase.Urgent, credit.phase(remainingMs = 8_000))
    }

    @Test
    fun phaseBeforeSpeaking() {
        assertEquals(DailyCredit.Phase.Calm, credit(remaining = 120_000).phase)
        assertEquals(DailyCredit.Phase.Warning, credit(remaining = 20_000).phase)
        assertEquals(DailyCredit.Phase.Exhausted, credit(remaining = 0).phase)
        assertEquals(DailyCredit.Phase.Calm, credit(remaining = 0, isUnlimited = true).phase)
    }

    @Test
    fun consumingIsTheEstimateHeldBetweenTwoAnswers() {
        val credit = credit(remaining = 10_000)

        val spent = credit.consuming(4_000)
        assertEquals(6_000, spent.remainingMs)

        // Jamais au-delà de la limite : un vocal toléré ne fait pas descendre
        // le reste sous zéro.
        val over = credit.consuming(20_000)
        assertEquals(DailyCredit.Catalog.limitMs, over.usedMs)
        assertTrue(over.isExhausted)

        assertEquals(credit, credit.consuming(0))
        assertEquals(credit, credit.consuming(-3))

        val subscriber = DailyCredit(isUnlimited = true, usedMs = 1_000)
        assertEquals(subscriber, subscriber.consuming(60_000))
    }

    // MARK: - Moins d'une seconde

    /**
     * Moins d'une seconde, c'est plus rien — la règle du serveur
     * (`EXHAUSTION_SLACK_MS`). Hors ligne, un vocal arrêté à 0:59,6 sur une
     * minute laissait 400 ms : le micro se rouvrait pour un vocal aussitôt
     * coupé, que le serveur refusait ensuite. L'estimation s'arrondit à
     * zéro, et un reste de 400 ms servi se lit épuisé.
     */
    @Test
    fun lessThanASecondLeftIsAnEmptyPot() {
        val spent = credit(remaining = 60_000).consuming(59_600)
        assertEquals(0, spent.remainingMs, "Arrondi à zéro, comme le serveur le fera.")
        assertTrue(spent.isExhausted)
        assertEquals(DailyCredit.Phase.Exhausted, spent.phase, "Le micro ne s'ouvre pas.")

        val crumbs = credit(remaining = 400)
        assertTrue(crumbs.isExhausted)
        assertEquals(DailyCredit.Phase.Exhausted, crumbs.phase)
        assertFalse(crumbs.allows(text = "abc"), "Cinq caractères tiendraient dans 400 ms : le pot est vide quand même.")
        assertEquals(0, crumbs.charactersLeft)

        // Une seconde pile reste une seconde.
        val second = credit(remaining = 1_000)
        assertFalse(second.isExhausted)
        assertEquals(DailyCredit.Phase.Urgent, second.phase)
        assertEquals(1_000, credit(remaining = 2_000).consuming(1_000).remainingMs)

        // Un abonné n'est jamais à court, quelques millisecondes ou pas.
        assertFalse(credit(remaining = 400, isUnlimited = true).isExhausted)
    }

    /**
     * La règle voyage avec le solde quand le serveur la sert ; sinon, celle
     * du catalogue.
     */
    @Test
    fun theSlackTravelsWithTheBalance() {
        val served = decode("""{"usedMs":299400,"exhaustionSlackMs":500}""")
        assertEquals(500, served.exhaustionSlackMs)
        assertFalse(served.isExhausted, "600 ms, au-dessus du seuil servi.")

        val older = decode("""{"usedMs":299400}""")
        assertEquals(1_000, older.exhaustionSlackMs)
        assertTrue(older.isExhausted)
    }

    // MARK: - Deux crédits gardés

    /** Le fuseau de Paris — le calendrier du test iOS. */
    private val paris: ZoneId = ZoneId.of("Europe/Paris")

    private fun at(day: Int, hour: Int = 0, minute: Int = 0): Instant =
        LocalDateTime.of(2026, 10, day, hour, minute).atZone(paris).toInstant()

    private fun midnight(after: Int): Instant = at(after + 1)

    /**
     * Le jour le plus tardif l'emporte, dans un sens comme dans l'autre :
     * le crédit épuisé d'hier ne passe pas devant celui de ce matin.
     */
    @Test
    fun theLaterDayWins() {
        val yesterday = DailyCredit(usedMs = 300_000, day = "2026-10-02", resetsAt = midnight(after = 2))
        val today = DailyCredit(usedMs = 60_000, day = "2026-10-03", resetsAt = midnight(after = 3))
        assertEquals(today, yesterday.merged(with = today))
        assertEquals(today, today.merged(with = yesterday))
    }

    /**
     * Le même jour, le plus consommé l'emporte : la consommation d'une
     * journée ne fait que croître. Le cache du matin (5:00) ne passe pas
     * devant celui de l'accueil relu après un vocal de 4 minutes.
     */
    @Test
    fun onTheSameDayTheMostSpentWins() {
        val morning = DailyCredit(usedMs = 0, day = "2026-10-03", resetsAt = midnight(after = 3))
        val afternoon = DailyCredit(usedMs = 240_000, day = "2026-10-03", resetsAt = midnight(after = 3))
        assertEquals(60_000, morning.merged(with = afternoon).remainingMs)
        assertEquals(60_000, afternoon.merged(with = morning).remainingMs)
    }

    /**
     * Illimité dès que l'un des deux le dit : un crédit servi avant l'achat
     * ne le sait pas encore.
     */
    @Test
    fun unlimitedAsSoonAsOneSaysSo() {
        val before = DailyCredit(usedMs = 240_000, day = "2026-10-03", resetsAt = midnight(after = 3))
        val after = DailyCredit(isUnlimited = true, usedMs = 0, day = "2026-10-03", resetsAt = midnight(after = 3))
        val merged = before.merged(with = after)
        assertTrue(merged.isUnlimited)
        assertEquals(240_000, merged.usedMs, "Le compte du voyage reste le plus avancé.")
        assertTrue(after.merged(with = before).isUnlimited)
    }

    /**
     * Un crédit rechargé n'a plus de `day` : il se range par son heure de
     * recharge. Plus tardive, elle l'emporte sur hier ; égale, c'est de
     * nouveau le plus consommé.
     */
    @Test
    fun aRefreshedCreditIsRankedByItsRecharge() {
        val morning = at(3, hour = 9)
        val yesterday = DailyCredit(usedMs = 300_000, day = "2026-10-02", resetsAt = midnight(after = 2))
        val refreshed = yesterday.refreshed(now = morning, zone = paris)
        assertNull(refreshed.day)
        assertEquals(0, yesterday.merged(with = refreshed).usedMs)
        assertEquals(0, refreshed.merged(with = yesterday).usedMs)

        val servedToday = DailyCredit(usedMs = 120_000, day = "2026-10-03", resetsAt = midnight(after = 3))
        assertEquals(servedToday, refreshed.merged(with = servedToday))
        assertEquals(servedToday, servedToday.merged(with = refreshed))
    }

    @Test
    fun mergingWithNothingKeepsWhatWeHave() {
        val known = credit(remaining = 90_000)
        assertEquals(known, known.merged(with = null))
        // Ni jour ni recharge : le plus consommé, faute de mieux.
        assertEquals(20, DailyCredit(usedMs = 10).merged(with = DailyCredit(usedMs = 20)).usedMs)
    }

    // MARK: - Un crédit gardé

    /**
     * Un crédit gardé de la veille repart plein : épuisé à 22 h 30, il ne
     * bloque plus le micro le lendemain matin, même hors ligne. Le barème et
     * l'abonnement restent ; la recharge suivante est le même minuit, un
     * jour plus tard.
     */
    @Test
    fun aKeptCreditFromYesterdayIsRefreshed() {
        val midnight = at(4)
        val morning = at(4, hour = 9)
        val yesterday = DailyCredit(
            limitMs = 300_000,
            usedMs = 300_000,
            textMsPerCharacter = 60,
            day = "2026-10-03",
            resetsAt = midnight,
        )

        val refreshed = yesterday.refreshed(now = morning, zone = paris)
        assertEquals(0, refreshed.usedMs)
        assertFalse(refreshed.isExhausted)
        assertEquals(60, refreshed.textMsPerCharacter, "Le barème servi reste.")
        assertNull(refreshed.day, "Le jour du serveur ne s'invente pas.")
        assertEquals(at(5), refreshed.resetsAt)

        // Ce qu'on consomme ensuite n'est pas effacé par une seconde lecture.
        val spent = refreshed.consuming(60_000)
        assertEquals(spent, spent.refreshed(now = morning, zone = paris))

        // Gardé plusieurs jours : la recharge suivante reste devant.
        val weekLater = at(10, hour = 23, minute = 59)
        assertEquals(at(11), yesterday.refreshed(now = weekLater, zone = paris).resetsAt)
    }

    /** Un crédit d'aujourd'hui, ou sans heure de recharge, se lit tel quel. */
    @Test
    fun aTodayCreditIsLeftAlone() {
        val resetsAt = Instant.now().plusSeconds(3_600)
        val today = DailyCredit(usedMs = 120_000, resetsAt = resetsAt)
        assertEquals(today, today.refreshed(now = Instant.now()))
        val undated = DailyCredit(usedMs = 120_000)
        assertEquals(undated, undated.refreshed(now = Instant.now()))
        val subscriber = DailyCredit(isUnlimited = true, usedMs = 0, resetsAt = Instant.now().minusSeconds(60))
        assertTrue(subscriber.refreshed(now = Instant.now()).isUnlimited)
    }

    /**
     * Le plus long tour qu'une journée laisse passer : la limite, et la
     * tolérance du serveur pour un vocal.
     */
    @Test
    fun theLongestTurnADayAllows() {
        val credit = DailyCredit()
        assertEquals(303_000, credit.limitWithTolerance(forVoice = true))
        assertEquals(300_000, credit.limitWithTolerance(forVoice = false))
    }

    // MARK: - L'écrit

    @Test
    fun aTextCostsSeventyFiveMillisecondsPerCharacter() {
        val credit = DailyCredit()
        assertEquals(225, credit.cost(ofText = "abc"))
        // 800 caractères valent une minute ; 4 000, tout le crédit.
        assertEquals(60_000, credit.cost(ofText = "a".repeat(800)))
        assertEquals(300_000, credit.cost(ofText = "a".repeat(4_000)))
    }

    @Test
    fun charactersAreCountedInUnicodeScalarsLikeTheServer() {
        // Le serveur compte `[...text].length` : des scalaires Unicode, ni des
        // graphèmes, ni des unités UTF-16 (`length` en Kotlin).
        val credit = DailyCredit()

        val decomposed = "é" // « é » en deux scalaires
        assertEquals(150, credit.cost(ofText = decomposed))

        val family = "👨‍👩‍👧" // une famille : trois personnes, deux liants
        assertEquals(8, family.length)
        assertEquals(5 * 75, credit.cost(ofText = family))
    }

    @Test
    fun aTextLongerThanTheRestDoesNotLeave() {
        val credit = credit(remaining = 60_000)
        assertTrue(credit.allows(text = "a".repeat(800)))
        assertFalse(credit.allows(text = "a".repeat(801)))
    }

    @Test
    fun charactersLeft() {
        assertEquals(2_400, credit(remaining = 180_000).charactersLeft)
        assertEquals(0, credit(remaining = 74).charactersLeft)
        assertEquals(0, DailyCredit(textMsPerCharacter = 0).charactersLeft)
    }

    // MARK: - Le décodage

    @Test
    fun decodesTheServedObject() {
        val credit = decode(
            """
            {
              "isUnlimited": false,
              "limitMs": 300000,
              "usedMs": 120000,
              "remainingMs": 180000,
              "textMsPerCharacter": 75,
              "warningRemainingMs": 30000,
              "urgentRemainingMs": 5000,
              "day": "2026-10-03",
              "resetsAt": "2026-10-03T22:00:00.000Z"
            }
            """,
        )

        assertFalse(credit.isUnlimited)
        assertEquals(120_000, credit.usedMs)
        assertEquals(180_000, credit.remainingMs)
        assertEquals("2026-10-03", credit.day)
        assertEquals(MemoBookDate.parse("2026-10-03T22:00:00.000Z"), credit.resetsAt)
    }

    @Test
    fun decodesAServerThatDoesNotServeTheScaleYet() {
        // Un serveur plus ancien ne doit faire tomber ni le fil ni les
        // réglages : on retombe sur le barème du catalogue.
        val credit = decode("""{"usedMs":42000}""")

        assertFalse(credit.isUnlimited)
        assertEquals(42_000, credit.usedMs)
        assertEquals(300_000, credit.limitMs)
        assertEquals(75, credit.textMsPerCharacter)
        assertEquals(30_000, credit.warningRemainingMs)
        assertEquals(5_000, credit.urgentRemainingMs)
        assertNull(credit.resetsAt)
    }

    @Test
    fun anUnreadableResetDateDoesNotSinkTheCredit() {
        val credit = decode("""{"usedMs":1000,"resetsAt":"demain"}""")
        assertEquals(1_000, credit.usedMs)
        assertNull(credit.resetsAt)
    }

    @Test
    fun tripSettingsReadTheNewKeyAndIgnoreTheOldOne() {
        // Le cache disque garde des réglages lus avant le crédit du jour, avec
        // leurs limites de souvenirs sous `memory`. Ils ne doivent pas se
        // relire comme un crédit plein inventé.
        val old = """
            { "tripId": "t", "name": "Rome", "walletBalance": 0,
              "memory": { "plan": "included", "used": 312, "allowance": 2000 },
              "wantsNotifications": true, "notifications": {}, "companions": [],
              "isPublicGallery": false, "isPrintable": false }
            """
        assertNull(MemoBookJson.decodeFromString(TripSettings.serializer(), old).dailyCredit)

        val new = """
            { "tripId": "t", "name": "Rome", "walletBalance": 0,
              "dailyCredit": { "isUnlimited": true, "usedMs": 0 },
              "wantsNotifications": true, "notifications": {}, "companions": [],
              "isPublicGallery": false, "isPrintable": false }
            """
        val settings = MemoBookJson.decodeFromString(TripSettings.serializer(), new)
        assertEquals(true, settings.dailyCredit?.isUnlimited)
    }

    // MARK: - Les textes

    @Test
    fun durations() {
        assertEquals("5 min", DailyCreditCopy.duration(300_000))
        assertEquals("3 min 20", DailyCreditCopy.duration(200_000))
        assertEquals("3 min 05", DailyCreditCopy.duration(185_000))
        assertEquals("45 s", DailyCreditCopy.duration(45_000))
        // Arrondi à la seconde inférieure : on n'annonce pas une demi-seconde
        // qui n'existe pas.
        assertEquals("29 s", DailyCreditCopy.duration(29_600))
        assertEquals("0 s", DailyCreditCopy.duration(-1_000))
    }

    @Test
    fun charactersUseTheFrenchThousandsSeparator() {
        assertEquals("1 caractère", DailyCreditCopy.characters(1))
        assertEquals("800 caractères", DailyCreditCopy.characters(800))
        val thousands = DailyCreditCopy.characters(2_650)
        assertTrue(thousands.startsWith("2"))
        assertTrue(thousands.endsWith("650 caractères"))
        assertFalse(thousands.contains(","))
        // L'espace fine insécable du `fr_FR` d'iOS, au caractère près.
        assertEquals("2 650 caractères", thousands)
    }

    @Test
    fun rowSaysWhatIsLeftOrUnlimited() {
        assertEquals("3 min 20 restantes", DailyCreditCopy.rowValue(credit(remaining = 200_000)))
        assertEquals("1 min restante", DailyCreditCopy.rowValue(credit(remaining = 60_000)))
        assertEquals("45 s restantes", DailyCreditCopy.rowValue(credit(remaining = 45_000)))
        assertEquals("Épuisé", DailyCreditCopy.rowValue(credit(remaining = 0)))
        assertEquals("Illimité", DailyCreditCopy.rowValue(credit(remaining = 0, isUnlimited = true)))
        assertEquals("5 min par jour pour tout le voyage", DailyCreditCopy.rowCaption(limitMs = 300_000))
    }

    @Test
    fun sheetSaysWhatIsLeftToday() {
        assertEquals("Il reste 3 min 20 aujourd’hui", DailyCreditCopy.Sheet.remaining(credit(remaining = 200_000)))
        assertEquals("Plus rien pour aujourd’hui : reviens demain", DailyCreditCopy.Sheet.remaining(credit(remaining = 0)))
        assertNull(DailyCreditCopy.Sheet.charactersEquivalent(credit(remaining = 0)))
        assertEquals(
            "soit environ 800 caractères à l’écrit",
            DailyCreditCopy.Sheet.charactersEquivalent(credit(remaining = 60_000)),
        )
    }

    @Test
    fun sheetReadsTheScaleFromTheBalance() {
        assertEquals(
            "5 minutes par jour pour ce voyage, à partager entre les co-voyageurs qui ne sont pas abonnés.",
            DailyCreditCopy.Sheet.sharing(limitMs = 300_000),
        )
        assertTrue(DailyCreditCopy.Sheet.consumption(textMsPerCharacter = 75).contains("800 caractères valent une minute"))
        assertEquals("1 minute", DailyCreditCopy.Sheet.spelledDuration(60_000))
        assertEquals("1 min 30", DailyCreditCopy.Sheet.spelledDuration(90_000))
        assertTrue(DailyCreditCopy.Sheet.unlimitedExplanation(limitMs = 300_000).contains("les 5 minutes du jour"))
    }

    @Test
    fun warningCountsDown() {
        assertEquals("Plus que 30 secondes avant la limite du jour", DailyCreditCopy.warning(remainingMs = 30_000))
        assertEquals("Plus qu’une seconde avant la limite du jour", DailyCreditCopy.warning(remainingMs = 1_400))
    }

    @Test
    fun visibleTextsUseTheTypographicApostrophe() {
        val texts = listOf(
            DailyCreditCopy.exhaustedMessage,
            DailyCreditCopy.exhaustedDetail,
            DailyCreditCopy.rowCaptionUnlimited,
            DailyCreditCopy.textTooLong(charactersLeft = 0),
            DailyCreditCopy.textTooLong(charactersLeft = 120),
            DailyCreditCopy.Sheet.recharge,
            DailyCreditCopy.Sheet.remaining(DailyCredit()),
            DailyCreditCopy.Sheet.consumption(textMsPerCharacter = 75),
            DailyCreditCopy.Sheet.unlimitedExplanation(limitMs = 300_000),
        )
        for (text in texts) {
            assertFalse(text.contains("'"), "apostrophe droite dans « $text »")
            assertFalse(text.contains("jeton", ignoreCase = true), text)
            assertFalse(text.contains("token", ignoreCase = true), text)
        }
    }

    // MARK: - Les corrections offertes (QA D8, 19/10/2026)

    /**
     * Les mêmes cas que le serveur (`test/dailyCredit.test.ts`) : les deux
     * côtés doivent tomber sur le même nombre.
     */
    @Test
    fun correctionMeasuresWhatChangedLikeTheServer() {
        assertEquals(3, CorrectionMeasure.changedCharacters("On a vu Famine.", "On a vu Fanny."))
        assertEquals(3, CorrectionMeasure.changedCharacters("Le chat dort.", "Le chien dort."))
        assertEquals(0, CorrectionMeasure.changedCharacters("Une phrase de trop. La suite.", "La suite."))
        val middle = " au milieu".repeat(200)
        assertEquals(3 + 4, CorrectionMeasure.changedCharacters("Famine$middle Rome", "Fanny$middle Roma"))
        val written = "Écrit 🙂"
        assertEquals(written.codePointCount(0, written.length), CorrectionMeasure.changedCharacters("", written))
    }

    @Test
    fun correctionIsFreeWithinWhatTheCardStillOffers() {
        val empty = credit(remaining = 0)
        val original = "Nous avons dîné avec Famine."
        val fixed = "Nous avons dîné avec Fanny."
        assertEquals(0, empty.cost(ofCorrection = fixed, replacing = original, freeLeft = 200))
        // Plus rien d'offert : chaque caractère modifié paie, comme un texte.
        assertEquals(3 * 75, empty.cost(ofCorrection = fixed, replacing = original, freeLeft = 0))
        // Un serveur d'avant ne dit rien : les 200 du barème.
        assertEquals(0, empty.cost(ofCorrection = fixed, replacing = original, freeLeft = null))
        assertEquals(
            0,
            credit(remaining = 0, isUnlimited = true).cost(ofCorrection = fixed, replacing = "", freeLeft = 0),
        )
    }

    @Test
    fun theRefusalBeyondTheFreeCharactersSaysWhatTheServerSays() {
        assertEquals(
            "Au-delà de 200 caractères modifiés, la correction passe par l’illimité.",
            DailyCreditCopy.correctionBeyondFree,
        )
    }
}
