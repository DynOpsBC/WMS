package com.dynops.bcwms

import android.content.Context
import com.dynops.bcwms.feature.TerminalSession
import org.json.JSONObject

/** BADE-only staged rollout. This policy is compiled only into BADE APKs. */
internal fun productionScreenAllowed(screen: Screen, environment: String, manager: Boolean): Boolean =
    !environment.trim().equals("Production", ignoreCase = true) || manager || screen !in setOf(
        Screen.Receiving, Screen.PutAway, Screen.Shipping,
        Screen.Packing, Screen.Picking, Screen.Production,
    )

internal fun isTerminalManager(profileJson: String): Boolean = runCatching {
    JSONObject(profileJson).optBoolean("terminalAdmin", false)
}.getOrDefault(false)

internal fun canOpenOperationalScreen(context: Context, screen: Screen): Boolean {
    val manager = TerminalSession.authenticated(context) &&
        isTerminalManager(BcApi.getLocalProfileJson(context))
    return productionScreenAllowed(screen, BcApi.getEnvironment(context), manager)
}
