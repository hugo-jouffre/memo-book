package com.memobook.feature

import com.memobook.networking.ApiConfiguration
import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals

class LaunchCopyTest {
    @Test
    fun theDeveloperLineNamesTheFallbackWhenThereIsOne() {
        val production = ApiConfiguration(URI("https://api-production-9f35a.up.railway.app"))
        val emulator = ApiConfiguration.effective(ApiConfiguration.localDevelopment, production, runsInEmulator = true)!!

        assertEquals(
            "API · http://10.0.2.2:3000 ↪︎ https://api-production-9f35a.up.railway.app",
            LaunchCopy.apiAddress(emulator),
        )
        assertEquals("API · https://api-production-9f35a.up.railway.app", LaunchCopy.apiAddress(production))
    }
}
