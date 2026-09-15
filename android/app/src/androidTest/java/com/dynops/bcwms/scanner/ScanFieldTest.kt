package com.dynops.bcwms.scanner

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ScanFieldTest {
    @get:Rule val compose = createComposeRule()

    private fun sendScannerKeys(text: String, suffix: Int) {
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        instrumentation.sendStringSync(text)
        instrumentation.sendKeyDownUpSync(suffix)
        compose.waitForIdle()
    }

    private fun commitScannerText(text: String) {
        androidx.test.espresso.Espresso.onView(org.hamcrest.Matchers.allOf(
            androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom(android.widget.EditText::class.java),
            androidx.test.espresso.matcher.ViewMatchers.withContentDescription("Palet"),
        )).perform(object : androidx.test.espresso.ViewAction {
            override fun getDescription() = "Deliver scanner text through the native InputConnection"
            override fun getConstraints() = androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom(android.widget.EditText::class.java)
            override fun perform(controller: androidx.test.espresso.UiController, view: android.view.View) {
                val connection = (view as android.widget.EditText).onCreateInputConnection(android.view.inputmethod.EditorInfo())
                org.junit.Assert.assertNotNull("Scanner requires an editable input connection", connection)
                connection.commitText(text, 1)
                controller.loopMainThreadUntilIdle()
            }
        })
        compose.waitForIdle()
    }

    @Test fun focusedHardwareScannerUsesTheCurrentWorkflowStep() {
        val destination = mutableStateOf("RAF-A")
        val accepted = mutableListOf<String>()
        compose.setContent {
            val currentDestination = destination.value
            MaterialTheme {
                ScanField("LP", "", {}, onScanned = { accepted += "$currentDestination:$it" })
            }
        }
        compose.onNodeWithText("LP").performClick()
        compose.runOnIdle { ScanBus.emit(ScanEvent("LP0001", "")) }
        compose.waitForIdle()
        compose.runOnIdle { destination.value = "RAF-B" }
        compose.waitForIdle()
        compose.runOnIdle { ScanBus.emit(ScanEvent("LP0002", "")) }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(listOf("RAF-A:LP0001", "RAF-B:LP0002"), accepted) }
    }

    @Test fun onlyFocusedFieldReceivesHardwareInput() {
        val accepted = mutableListOf<String>()
        compose.setContent {
            MaterialTheme { Column {
                ScanField("Kaynak", "", {}, onScanned = { accepted += "kaynak:$it" })
                ScanField("Hedef", "", {}, onScanned = { accepted += "hedef:$it" })
            } }
        }
        compose.onNodeWithText("Kaynak").performClick()
        compose.runOnIdle { ScanBus.emit(ScanEvent("A-01", "")) }
        compose.waitForIdle()
        compose.onNodeWithText("Hedef").performClick()
        compose.runOnIdle { ScanBus.emit(ScanEvent("B-01", "")) }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(listOf("kaynak:A-01", "hedef:B-01"), accepted) }
    }

    @Test fun disabledFieldCannotSubmitBufferedHardwareInput() {
        val enabled = mutableStateOf(true)
        val accepted = mutableListOf<String>()
        compose.setContent {
            MaterialTheme { ScanField("LP", "", {}, enabled = enabled.value, onScanned = { accepted += it }) }
        }
        compose.onNodeWithText("LP").performClick()
        compose.runOnIdle { enabled.value = false }
        compose.waitForIdle()
        compose.runOnIdle { ScanBus.emit(ScanEvent("LP0001", "")) }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(emptyList<String>(), accepted) }
    }

    @Test fun manualPutAwayInputCanBeConfirmedAndBlankInputExplainsWhatToDo() {
        val accepted = mutableListOf<String>()
        compose.setContent {
            var value by remember { mutableStateOf("") }
            MaterialTheme { ScanField("LP okut veya yaz", value, { value = it }, onScanned = { accepted += it }) }
        }
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithText("Önce okutun ya da elle yazın: LP okut veya yaz").assertIsDisplayed()
        compose.onNodeWithText("LP okut veya yaz").performTextInput("LP000005")
        compose.onNodeWithText("OK").performClick()
        compose.runOnIdle { assertEquals(listOf("LP000005"), accepted) }
    }

    @Test fun mandatoryPickingStillAcceptsHardwareInputWithoutManualConfirmation() {
        val accepted = mutableListOf<String>()
        compose.setContent {
            MaterialTheme { ScanField("Paletin QR kodunu okut", "", {}, scanOnly = true, onScanned = { accepted += it }) }
        }
        compose.onNodeWithText("OK").assertDoesNotExist()
        compose.onNodeWithText("Paletin QR kodunu okut").performClick()
        compose.runOnIdle { ScanBus.emit(ScanEvent("LP000005", "")) }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(listOf("LP000005"), accepted) }
    }

    @Test fun pickingAcceptsKeyboardWedgeEnterAndTabAndKeepsFocusForNextPallet() {
        val accepted = mutableListOf<String>()
        compose.setContent {
            MaterialTheme { ScanField("Palet", "", {}, scanOnly = true, updateValueOnScan = false, onScanned = { accepted += it }) }
        }
        val field = compose.onNodeWithText("Palet")
        field.performClick().assertIsFocused()
        // Inject native hardware key events, not a ScanBus shortcut.
        sendScannerKeys("LP000001", android.view.KeyEvent.KEYCODE_ENTER)
        compose.waitForIdle()
        field.assertIsFocused()
        sendScannerKeys("LP000002", android.view.KeyEvent.KEYCODE_TAB)
        compose.waitForIdle()
        field.assertIsFocused()
        compose.runOnIdle { assertEquals(listOf("LP000001", "LP000002"), accepted) }
    }

    @Test fun pickingAcceptsImeScannerTextWithAndWithoutStringSuffix() {
        val accepted = mutableListOf<String>()
        compose.setContent {
            MaterialTheme { ScanField("Palet", "", {}, scanOnly = true, onScanned = { accepted += it }) }
        }
        val field = compose.onNodeWithText("Palet")
        field.performClick()
        commitScannerText("LP000005\r\n")
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(listOf("LP000005"), accepted) }
        commitScannerText("LP000006")
        compose.onNodeWithText("Okunan Paleti Doğrula").assertIsDisplayed().performClick()
        field.assertIsFocused()
        compose.runOnIdle { assertEquals(listOf("LP000005", "LP000006"), accepted) }
    }

    @Test fun scannerFocusDoesNotOpenSoftwareKeyboard() {
        compose.setContent { MaterialTheme { ScanField("Palet", "", {}, scanOnly = true, onScanned = {}) } }
        compose.onNodeWithText("Palet").performClick()
        androidx.test.espresso.Espresso.onView(androidx.test.espresso.matcher.ViewMatchers.withContentDescription("Palet"))
            .check(androidx.test.espresso.assertion.ViewAssertions.matches(androidx.test.espresso.matcher.ViewMatchers.hasFocus()))
        compose.onNodeWithText("Palet").assertIsFocused()
        compose.waitForIdle()
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val activity = androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED).single()
            val insets = androidx.core.view.ViewCompat.getRootWindowInsets(activity.window.decorView)
            org.junit.Assert.assertFalse(insets?.isVisible(androidx.core.view.WindowInsetsCompat.Type.ime()) == true)
        }
    }

    @Test fun scannerDiscardsPartialCodeWhenDisabledAndUsesCurrentCallbackAfterReload() {
        val enabled = mutableStateOf(true)
        val step = mutableStateOf("old")
        val accepted = mutableListOf<String>()
        compose.setContent {
            val currentStep = step.value
            MaterialTheme { ScanField("Palet", "", {}, scanOnly = true, enabled = enabled.value,
                onScanned = { accepted += "$currentStep:$it" }) }
        }
        compose.onNodeWithText("Palet").performClick()
        commitScannerText("LP000001")
        compose.runOnIdle { enabled.value = false }
        compose.onNodeWithText("Palet").assertIsNotEnabled()
        compose.onNodeWithText("Okunan Paleti Doğrula").assertDoesNotExist()
        compose.runOnIdle { step.value = "new"; enabled.value = true }
        compose.onNodeWithText("Palet").performClick()
        commitScannerText("LP000002\t")
        compose.runOnIdle { assertEquals(listOf("new:LP000002"), accepted) }
    }
}
