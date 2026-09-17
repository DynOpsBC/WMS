package com.dynops.bcwms.feature

import androidx.compose.runtime.Composable
import org.json.JSONObject

// BADE terminal reassignment policy is not part of this customer build.
@Suppress("UNUSED_PARAMETER")
internal fun terminalSelectionAllowed(current: String, next: String, managerProfile: JSONObject?): Boolean = true

@Suppress("UNUSED_PARAMETER")
@Composable
internal fun TerminalChangeDialog(gateway: TerminalLoginGateway, onDismiss: () -> Unit, onChanged: () -> Unit) = Unit
