package com.memobook.feature.bookpreview

import com.memobook.core.BookPreview
import com.memobook.core.BookPreviewStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/**
 * Le chemin vers les couvertures, posé sur la première et la dernière page de
 * l'aperçu (Hugo, 30/09/2026, maquette `3545:21634`) — **même sans PDF** :
 * l'aperçu de l'app vit encore sur son jeu d'essai, et le garde-fou d'avant
 * l'effaçait partout. Porté de `BookPreviewCoverTests.swift`, cas pour cas.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BookPreviewCoverTest {
    private suspend fun model(hasConfiguredCovers: Boolean): BookPreviewModel {
        val preview = BookPreview(
            memoId = "memo",
            title = "Rome",
            status = BookPreviewStatus.Ready,
            pageCount = 10,
            hasConfiguredCovers = hasConfiguredCovers,
        )
        val model = BookPreviewModel(memoId = "memo", source = { preview })
        model.run()
        return model
    }

    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test fun theFirstAndLastPagesInviteToConfigureTheCoversWithoutAPdf() = runTest {
        val model = model(hasConfiguredCovers = false)
        assertEquals(BookPreviewModel.Stage.Preview, model.stage)

        assertEquals(CoverCallToAction.Invitation, model.coverCallToAction)
        model.show(sheet = 9)
        assertEquals(CoverCallToAction.Invitation, model.coverCallToAction, "La quatrième de couverture aussi.")
        model.show(sheet = 4)
        assertNull(model.coverCallToAction, "Une page du récit ne mène pas aux couvertures.")
    }

    @Test fun onceChosenBothCoversKeepTheirConfigureButton() = runTest {
        val model = model(hasConfiguredCovers = true)

        assertEquals(CoverCallToAction.Edit, model.coverCallToAction)
        assertFalse(model.isOnConfigurableCover, "Plus de voile une fois les couvertures choisies.")
        model.show(sheet = 9)
        assertEquals(CoverCallToAction.Edit, model.coverCallToAction)
    }
}
