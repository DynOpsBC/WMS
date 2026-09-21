package com.dynops.bcwms.feature

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import kotlinx.coroutines.launch
import org.junit.Rule
import org.junit.Test

class PickTakeoverUiTest {
    @get:Rule val compose = createComposeRule()
    @Test fun takeoverRequiresExplicitConfirmationAndCanBeCancelled() {
        compose.setContent {
            MaterialTheme {
                val confirm = rememberPickTakeoverConfirmation()
                val scope = rememberCoroutineScope()
                var result by remember { mutableStateOf("Bekliyor") }
                androidx.compose.foundation.layout.Column {
                    Button(onClick = { scope.launch {
                        result = if (confirm("PI001730", "DYNOPS")) "Onaylandı" else "İptal edildi"
                    } }) { Text("Bana Ata") }
                    Text(result)
                }
            }
        }
        compose.onNodeWithText("Bana Ata").performClick()
        compose.onNodeWithText("Belgeyi devralmak istediğinize emin misiniz?").assertIsDisplayed()
        compose.onNodeWithText("PI001730 belgesi DYNOPS", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Vazgeç").performClick()
        compose.onNodeWithText("İptal edildi").assertExists()
        compose.onNodeWithText("Bana Ata").performClick()
        compose.onNodeWithText("Evet, Bana Ata").performClick()
        compose.onNodeWithText("Onaylandı").assertExists()
        compose.onNodeWithText("Belgeyi devralmak istediğinize emin misiniz?").assertDoesNotExist()
    }
}
