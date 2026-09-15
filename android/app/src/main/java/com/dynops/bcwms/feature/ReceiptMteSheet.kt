package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun receiptMteLpNos(receiptNo: String, lines: List<JSONObject>): List<String> = lines
    .filter {
        it.optString("sourceDocumentType") == "WhseReceipt" &&
            it.optString("sourceDocumentNo") == receiptNo &&
            it.optString("itemNo").isNotBlank() && it.optDouble("quantity", 0.0) > 0.0
    }
    .map { it.optString("lpNo").trim() }
    .filter(String::isNotBlank)
    .distinct()
    .sorted()

/** Posting already requested labels. Reprinting is explicit, with no initial selection. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReceiptMteSheet(receiptNo: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var lpNos by remember(receiptNo) { mutableStateOf<List<String>>(emptyList()) }
    var selected by remember(receiptNo) { mutableStateOf<Set<String>>(emptySet()) }
    var busy by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }

    fun load() {
        scope.launch {
            busy = true
            loaded = false
            status = "Mal kabule ait LP'ler yükleniyor..."
            val safeNo = receiptNo.replace("'", "''")
            val page = BcApi.getAllPages(
                context,
                "licensePlateLines?\$filter=sourceDocumentType eq 'WhseReceipt' and sourceDocumentNo eq '$safeNo' and quantity gt 0",
            )
            loaded = page.complete
            lpNos = if (page.complete) receiptMteLpNos(receiptNo, page.rows) else emptyList()
            selected = selected.intersect(lpNos.toSet())
            status = when {
                !page.complete -> "HATA: LP listesi tamamlanamadı. Yenileyin; mal kabulü tekrar kaydetmeyin."
                lpNos.isEmpty() -> "Bu mal kabule bağlı ürün içeren LP bulunamadı. MTE için LP oluşturulmuş olmalı."
                else -> "${lpNos.size} LP bulundu. Yalnız etiketi eksik olanları seçin."
            }
            busy = false
        }
    }
    LaunchedEffect(receiptNo) { load() }

    ModalBottomSheet(
        onDismissRequest = { if (!busy) onDismiss() },
        sheetState = rememberModalBottomSheetState(
            skipPartiallyExpanded = true,
            confirmValueChange = { it != SheetValue.Hidden || !busy },
        ),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Mal kabul kaydedildi · MTE", style = MaterialTheme.typography.titleLarge)
            Text("Belge: $receiptNo")
            Text(
                "Kayıt sırasında etiket basımı istendi. Çıktıları kontrol edin; " +
                    "yalnız eksikleri yeniden yazdırın. Liste bu belgenin önceki kısmi kabullerine ait LP'leri de içerebilir.",
                style = MaterialTheme.typography.bodySmall,
            )
            StatusText(status)
            LazyColumn(Modifier.weight(1f, fill = false)) {
                items(lpNos, key = { it }) { lpNo ->
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = lpNo in selected,
                            enabled = !busy,
                            onCheckedChange = { checked -> selected = if (checked) selected + lpNo else selected - lpNo },
                        )
                        Text(lpNo)
                    }
                }
            }
            Button(
                enabled = loaded && !busy && selected.isNotEmpty(),
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    val requested = selected.toList()
                    scope.launch {
                        busy = true
                        val failures = linkedMapOf<String, String>()
                        val route = mtePrintRoute(getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT))
                        requested.forEachIndexed { index, lpNo ->
                            status = "MTE gönderiliyor: ${index + 1}/${requested.size}"
                            // A draft or emptied LP must not produce a misleading successful reprint.
                            val safeLp = lpNo.replace("'", "''")
                            val response = BcApi.get(context, "licensePlates('$safeLp')")
                            val header = if (response.ok) runCatching { JSONObject(response.body) }.getOrNull() else null
                            if (header == null || !canPrintMte(
                                    linesComplete = header.has("lineCount") && header.has("pendingReceiptNo"),
                                    lineCount = header.optInt("lineCount"),
                                    pendingReceiptNo = header.optString("pendingReceiptNo"),
                                )) {
                                failures[lpNo] = "LP içeriği doğrulanamadı veya LP henüz mal kabulü bekliyor."
                            } else {
                                val result = BcApi.boundActionLongRunning(
                                    context, "licensePlates", lpNo, route.action,
                                    JSONObject().put("printerId", route.printerCode).put("copies", 1).toString(),
                                )
                                if (!result.ok) failures[lpNo] = QcErrorParser.friendlyStatus(BcApi.errorMessage(result.body), result.httpCode)
                            }
                        }
                        // No automatic retry: a network failure can occur after physical printing.
                        selected = emptySet()
                        status = if (failures.isEmpty()) {
                            "TAMAM: ${requested.size} LP için MTE isteği gönderildi. Fiziksel çıktıları kontrol edin."
                        } else {
                            "UYARI: ${failures.size} LP için baskı doğrulanamadı: ${failures.keys.joinToString()}. " +
                                "${failures.values.first()} Tekrar seçmeden önce çıktıları kontrol edin. Mal kabul kaydedildi."
                        }
                        busy = false
                    }
                },
            ) { Text("Seçilen MTE'leri Yazdır (${selected.size})") }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = { load() }, enabled = !busy) { Text("Yenile") }
                TextButton(onClick = onDismiss, enabled = !busy) { Text("Devam Et") }
            }
        }
    }
}
