package com.dynops.bcwms.feature

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.dynops.bcwms.BcApi
import org.json.JSONObject

internal fun activePrinterPath(code: String): String {
    val key = java.net.URLEncoder.encode(code.replace("'", "''"), "UTF-8").replace("+", "%20")
    return "printers('$key')"
}

/** printerHandle is populated from Print Agent's printerName, unlike the editable description. */
internal fun activePrinterAgentName(body: String, expectedCode: String): String? = runCatching {
    val row = JSONObject(body)
    if (row.optString("code") != expectedCode) null
    else row.optString("printerHandle").takeIf { it.isNotBlank() }
}.getOrNull()

@Composable
internal fun ActiveLabelPrinter(modifier: Modifier = Modifier, refreshKey: Any) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var preferenceRevision by remember { mutableIntStateOf(0) }
    var resumeRevision by remember { mutableIntStateOf(0) }
    DisposableEffect(context, lifecycle) {
        val prefs = context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> preferenceRevision++ }
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) resumeRevision++
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        lifecycle.addObserver(observer)
        onDispose {
            prefs.unregisterOnSharedPreferenceChangeListener(listener)
            lifecycle.removeObserver(observer)
        }
    }
    val selection = remember(preferenceRevision) {
        Triple(TerminalSession.scope(context), TerminalSession.code(context), getDefaultPrinter(context))
    }
    val printerCode = selection.third
    var printerName by remember(selection) { mutableStateOf<String?>(null) }
    var loading by remember(selection) { mutableStateOf(printerCode.isNotBlank()) }
    LaunchedEffect(selection, refreshKey, resumeRevision) {
        if (printerCode.isBlank()) return@LaunchedEffect
        loading = true
        try {
            val response = BcApi.get(context, activePrinterPath(printerCode))
            printerName = if (response.ok) activePrinterAgentName(response.body, printerCode) else null
        } finally { loading = false }
    }
    Column(modifier) {
        Text("Etiket yazıcısı", style = MaterialTheme.typography.labelMedium)
        Text(
            when {
                printerCode.isBlank() -> "Seçilmemiş"
                printerName != null -> printerName!!
                loading -> "Yükleniyor…"
                else -> "Yazıcı adı alınamadı"
            },
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
