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
}
