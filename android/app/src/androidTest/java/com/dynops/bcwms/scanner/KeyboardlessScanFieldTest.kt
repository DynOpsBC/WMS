package com.dynops.bcwms.scanner

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test

/** Kitoko: okutma alanı klavye açmadan klavye-kama ve DataWedge okutmasını alır. */
class KeyboardlessScanFieldTest {
    @get:Rule val compose = createComposeRule()

    private fun onEditor(label: String) = androidx.test.espresso.Espresso.onView(org.hamcrest.Matchers.allOf(
        androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom(android.widget.EditText::class.java),
        androidx.test.espresso.matcher.ViewMatchers.withContentDescription(label),
    ))

    private fun commit(label: String, text: String) {
        onEditor(label).perform(object : androidx.test.espresso.ViewAction {
            override fun getDescription() = "commit scanner text"
            override fun getConstraints() = androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom(android.widget.EditText::class.java)
            override fun perform(controller: androidx.test.espresso.UiController, view: android.view.View) {
                val c = (view as android.widget.EditText).onCreateInputConnection(android.view.inputmethod.EditorInfo())
                org.junit.Assert.assertNotNull(c)
                c.commitText(text, 1)
                controller.loopMainThreadUntilIdle()
            }
        })
        compose.waitForIdle()
    }

    private fun imeVisible(): Boolean {
        var visible = false
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val activity = androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED).single()
            visible = androidx.core.view.ViewCompat.getRootWindowInsets(activity.window.decorView)
                ?.isVisible(androidx.core.view.WindowInsetsCompat.Type.ime()) == true
        }
        return visible
    }

    @Test fun wedgeScanWithEnterSubmitsWithoutKeyboard() {
        val accepted = mutableListOf<String>()
        val value = mutableStateOf("")
        compose.setContent {
            MaterialTheme { ScanField("Raf okut", value.value, { value.value = it }, suppressKeyboard = true, onScanned = { accepted += it }) }
        }
        compose.onNodeWithText("Raf okut").performClick()
        compose.waitForIdle()
        assertFalse(imeVisible())
        commit("Raf okut", "A-01\n")
        compose.runOnIdle {
            assertEquals(listOf("A-01"), accepted)
            assertEquals("A-01", value.value)
        }
        assertFalse(imeVisible())
    }

    @Test fun okButtonSubmitsCommittedTextAndScreenCanClearValue() {
        val accepted = mutableListOf<String>()
        val value = mutableStateOf("")
        compose.setContent {
            MaterialTheme { ScanField("LP okut", value.value, { value.value = it }, suppressKeyboard = true, onScanned = { accepted += it; value.value = "" }) }
        }
        compose.onNodeWithText("LP okut").performClick()
        commit("LP okut", "LP000005")
        compose.onNodeWithText("OK").performClick()
        compose.runOnIdle { assertEquals(listOf("LP000005"), accepted) }
        compose.runOnIdle { assertEquals("", value.value) }
        commit("LP okut", "LP000006\r\n")
        compose.runOnIdle { assertEquals(listOf("LP000005", "LP000006"), accepted) }
    }

    @Test fun focusedFieldStillReceivesDataWedgeIntent() {
        val accepted = mutableListOf<String>()
        compose.setContent {
            var v by remember { mutableStateOf("") }
            MaterialTheme { ScanField("Ürün okut", v, { v = it }, suppressKeyboard = true, onScanned = { accepted += it }) }
        }
        compose.onNodeWithText("Ürün okut").performClick()
        compose.waitForIdle()
        compose.runOnIdle { ScanBus.emit(ScanEvent("1000", "")) }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(listOf("1000"), accepted) }
    }
}
