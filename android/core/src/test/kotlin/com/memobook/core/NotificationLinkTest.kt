package com.memobook.core

import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Les liens que le serveur met dans ses notifications — au chemin près de
 * `NOTIFICATION_LINKS` (`backend/src/services/notificationPlanner.ts`). Mêmes cas
 * que `NotificationLinkTests.swift` et `InviteLinkTests.swift`.
 */
class NotificationLinkTest {
    private val trip = "6f1c2e7a-3b2d-4c55-9a7e-0d4b8f2a1c90"
    private val production = URI("https://api-production-9f35a.up.railway.app")

    private fun link(string: String) = NotificationLink.from(URI(string))

    @Test
    fun eachServerLinkOpensItsScreen() {
        assertEquals(NotificationLink.Subscription, link("memobook://subscription"))
        assertEquals(NotificationLink.NewTrip, link("memobook://trips/new"))
        assertEquals(NotificationLink.Chat(trip), link("memobook://trips/$trip/chat"))
        assertEquals(NotificationLink.BookPreview(trip), link("memobook://trips/$trip/preview"))
    }

    /** La cagnotte est partie (T230), mais des notifications de fin de voyage
     *  déjà livrées portent son lien : il ouvre l'aperçu du carnet. */
    @Test
    fun theFormerWalletLinkOpensTheBookPreview() {
        assertEquals(NotificationLink.BookPreview(trip), link("memobook://trips/$trip/wallet"))
    }

    @Test
    fun theFormerPaywallLinkStillOpensTheOffer() {
        assertEquals(NotificationLink.Paywall, link("memobook://paywall"))
    }

    @Test
    fun otherLinksOfTheAppAreNotNotifications() {
        // Ceux-là ont leur propre chemin : le retour de Stripe, l'e-mail.
        assertNull(link("memobook://stripe-redirect"))
        assertNull(link("memobook://password/reset?token=abc"))
        assertNull(link("memobook://trips/abc/unknown"))
        assertNull(link("https://memo-book.com/paywall"))
    }

    @Test
    fun thePayloadKeyIsReadAsALink() {
        assertEquals(NotificationLink.Subscription, NotificationLink.from("memobook://subscription"))
        assertNull(NotificationLink.from(null as String?))
        assertNull(NotificationLink.from("pas un lien"))
    }

    @Test
    fun theAppLinkCarriesTheCode() {
        val uri = URI("https://api-production-9f35a.up.railway.app/j/JHKFDA")
        assertEquals("JHKFDA", InviteLink.code(uri))
        assertEquals(NotificationLink.Join("JHKFDA"), NotificationLink.from(uri))
    }

    @Test
    fun theFallbackPageOpensTheAppWithTheCode() {
        assertEquals(NotificationLink.Join("JHKFDA"), link("memobook://join?code=jhk-fda"))
        assertEquals(NotificationLink.Join("JHKFDA"), link("memobook://j/JHKFDA"))
    }

    @Test
    fun otherLinksAreNotInvitations() {
        assertNull(InviteLink.code(URI("https://api-production-9f35a.up.railway.app/password/reset")))
        assertNull(InviteLink.code(URI("memobook://join")))
    }

    @Test
    fun theSharedLinkPointsAtTheInvitePath() {
        assertEquals(
            "https://api-production-9f35a.up.railway.app/j/JHKFDA",
            InviteLink.url("JHKFDA", production).toString(),
        )
        assertNull(InviteLink.url("JHKFDA", null))
    }

    @Test
    fun theResetLinkGivesItsToken() {
        assertEquals("abc", PasswordResetLink.token(URI("memobook://password/reset?token=abc")))
        assertEquals(
            "abc",
            PasswordResetLink.token(URI("https://api-production-9f35a.up.railway.app/password/reset?token=abc")),
        )
        assertNull(PasswordResetLink.token(URI("memobook://password/reset")))
        assertNull(PasswordResetLink.token(URI("memobook://password/reset?token=")))
        assertNull(PasswordResetLink.token(URI("memobook://trips/new?token=abc")))
    }
}
