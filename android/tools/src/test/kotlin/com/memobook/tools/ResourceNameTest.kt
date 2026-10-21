package com.memobook.tools

import kotlin.test.Test
import kotlin.test.assertEquals

class ResourceNameTest {
    @Test
    fun iosNamesBecomeAndroidResourceNames() {
        assertEquals("icon_printer_duo", resourceName("IconPrinterDuo"))
        assertEquals("icon_desktop_pc_checked1_duo", resourceName("IconDesktopPCChecked1Duo"))
        assertEquals("icon_pdf", resourceName("IconPDF"))
        assertEquals("icon_lucide_building2", resourceName("IconLucideBuilding2"))
        assertEquals("logo_memobook_creme", resourceName("LogoMemobookCreme"))
        assertEquals("connector_polar_steps", resourceName("ConnectorPolarSteps"))
    }
}
