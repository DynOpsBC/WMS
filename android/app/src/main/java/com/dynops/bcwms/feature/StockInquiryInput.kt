package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.scanner.ScanBus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Finish cancellation before starting the latest scan, so old results cannot overwrite it. */
internal class LatestStockInquiry(private val scope: CoroutineScope) {
    private var job: Job? = null

    fun submit(block: suspend () -> Unit) {
        val previous = job
        previous?.cancel()
        job = scope.launch {
            withContext(NonCancellable) { previous?.join() }
            kotlin.coroutines.coroutineContext.ensureActive()
            block()
        }
    }

    fun cancel() { job?.cancel() }
}

internal fun routeStockInquiryScan(raw: String, onQuery: (String) -> Unit, onItem: (String) -> Unit, onLp: (LpScanRef) -> Unit) {
    val resolved = BarcodeIntentResolver.resolve(raw)
    val value = resolved.itemNo ?: resolved.value
    onQuery(value)
    val lp = lpScanRef(raw)
    if (lp != null) onLp(lp) else onItem(value)
}

/** Screen-level listener stays composed when the query field scrolls off screen. */
@Composable
internal fun StockInquiryScanListener(enabled: Boolean, onScan: (String) -> Unit) {
    val callback by rememberUpdatedState(onScan)
    val focused = LocalWindowInfo.current.isWindowFocused
    LaunchedEffect(enabled, focused) {
        if (enabled && focused) ScanBus.events.collect { callback(it.raw) }
    }
}

@Composable
internal fun StockInquiryInput(
    query: String,
    onQuery: (String) -> Unit,
    loading: Boolean,
    printing: Boolean,
    onItem: (String) -> Unit,
    onLp: (LpScanRef) -> Unit,
) {
    fun submit(raw: String) {
        routeStockInquiryScan(raw, onQuery, onItem, onLp)
    }
    ScanField("Ürün No / LP No", query, onQuery, modifier = Modifier.fillMaxWidth(),
        enabled = !printing, listenScanBus = false, onScanned = ::submit)
    Spacer(Modifier.height(8.dp))
    Button(onClick = { submit(query) }, enabled = !loading && !printing && query.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
        Text(if (loading) "Sorgulanıyor…" else "🔎 Sorgula", fontWeight = FontWeight.Bold)
    }
}
