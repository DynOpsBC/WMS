package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Existing thermal label actions retain the configured BC label design.
 * Kitoko (19 Eki 2026): DKÇ/EMU "Etiket Çıkar" ekranı; raf ve ürün sekmeleri
 * Bin/Ürün Sorgu modüllerinin labelsOnly akışını açar.
 */
@Composable
fun LabelsModule() {
    var tab by remember { mutableStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Raf Etiketi") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Ürün Etiketi") })
            // Kitoko (22 Eki 2026): LP okut → içerik + LP / lot etiketi.
            Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text("LP Etiketi") })
        }
        Box(Modifier.weight(1f)) {
            when (tab) {
                0 -> BinInquiryModule(labelsOnly = true)
                1 -> ItemInquiryModule(labelsOnly = true)
                else -> LpLabelTab()
            }
        }
    }
}

/**
 * Kitoko (22 Eki 2026): Etiket Çıkar → LP Etiketi. LP QR'ı (LP No) ya da SSCC
 * okutulur veya yazılır; LP kartı içerikle açılır, LP / lot etiketi buradan basılır.
 */
@Composable
private fun LpLabelTab() {
    var query by remember { mutableStateOf("") }
    var ref by remember { mutableStateOf<LpScanRef?>(null) }
    fun open(raw: String) {
        val value = raw.trim()
        if (value.isEmpty()) return
        ref = lpScanRef(value) ?: LpScanRef.ByNo(value.uppercase())
        query = ref?.value.orEmpty()
    }
    // Alan odakta değilken de (ör. yazdırdıktan sonra) donanım okutması yeni LP'yi açar.
    LpScanListener(enabled = true) { open(it.value) }
    Column(Modifier.fillMaxSize()) {
        com.dynops.bcwms.scanner.ScanField(
            "LP No / SSCC (LP QR'ı okutun)", query, { query = it },
            modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 12.dp),
            onScanned = { open(it) },
        )
        val current = ref
        if (current == null) {
            Text(
                "LP etiketindeki QR'ı okutun: LP'nin içeriği (ürün, lot, SKT, miktar) açılır; LP etiketi ve lot etiketi buradan basılır.",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(12.dp),
            )
        } else {
            LpContentCard(ref = current, onClose = { ref = null; query = "" }, closeLabel = "× Kapat", modifier = Modifier.weight(1f))
        }
    }
}
