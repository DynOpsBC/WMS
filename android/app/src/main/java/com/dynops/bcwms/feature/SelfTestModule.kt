package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.ScanBus
import com.dynops.bcwms.scanner.ScanEvent
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

/**
 * Mobil app sağlık paneli. Müşteri ortamına kurulum / hand-off sonrası
 * operatörün veya yöneticinin "her şey çalışıyor mu?" diye tek dokunuşla
 * doğrulayabilmesi için 10 ayrı check'i sırayla yürütür ve PASS/FAIL/SKIP
 * raporu üretir.
 *
 * Web tarafındaki [web/src/pages/SelfTest.tsx] ile aynı katalogu paylaşır
 * (paralel evrim için isimler birebir eşleşir).
 */

private enum class CheckStatus { PENDING, RUNNING, PASS, FAIL, SKIP }

private data class CheckResult(
    val id: String,
    val title: String,
    val status: CheckStatus,
    val message: String = "",
    val durationMs: Long = 0,
)

@Composable
fun SelfTestModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf(false) }
    var results by remember { mutableStateOf<List<CheckResult>>(initialChecks()) }

    fun update(id: String, status: CheckStatus, message: String = "", durationMs: Long = 0) {
        results = results.map { if (it.id == id) it.copy(status = status, message = message, durationMs = durationMs) else it }
    }

    suspend fun timed(id: String, block: suspend () -> Pair<CheckStatus, String>) {
        update(id, CheckStatus.RUNNING)
        val start = System.currentTimeMillis()
        val (status, msg) = try { block() } catch (e: Exception) { CheckStatus.FAIL to "exception: ${e.message ?: e.javaClass.simpleName}" }
        update(id, status, msg, System.currentTimeMillis() - start)
    }

    fun runAll() {
        if (running) return
        running = true
        results = initialChecks()
        scope.launch {
            // 1. Token saved
            timed("token") {
                if (BcApi.hasToken(context)) CheckStatus.PASS to "Bağlantı tokenı kayıtlı"
                else CheckStatus.FAIL to "Token yok — Bağlantı Ayarları'ndan giriş yapın"
            }
            val hasToken = BcApi.hasToken(context)

            // 2. BC reachable (warehouse API)
            timed("bc_warehouse") {
                if (!hasToken) return@timed CheckStatus.SKIP to "Token gerek"
                val r = BcApi.testConnection(context)
                if (r.ok) CheckStatus.PASS to "warehouse/v2.0 ulaşılabilir (HTTP ${r.httpCode})"
                else CheckStatus.FAIL to "HTTP ${r.httpCode} · ${BcApi.errorMessage(r.body).take(120)}"
            }

            // 3. Standard items fallback (BC v2.0)
            timed("bc_standard") {
                if (!hasToken) return@timed CheckStatus.SKIP to "Token gerek"
                val r = BcApi.getWithStandardFallback(context, "items?\$top=1")
                if (r.ok) CheckStatus.PASS to "items endpoint çalışıyor (HTTP ${r.httpCode})"
                else CheckStatus.FAIL to "HTTP ${r.httpCode}"
            }

            // 4. ItemApi inventory FlowField calc (Codex Finding 6 regression guard)
            timed("item_inventory") {
                if (!hasToken) return@timed CheckStatus.SKIP to "Token gerek"
                val r = BcApi.get(context, "items?\$top=1&\$select=no,inventory,quantityOnPurchOrder,quantityOnSalesOrder")
                if (!r.ok) return@timed CheckStatus.FAIL to "items query HTTP ${r.httpCode}"
                val first = BcApi.parseValueArray(r.body).firstOrNull()
                    ?: return@timed CheckStatus.SKIP to "Hiç item yok"
                if (!first.has("inventory")) return@timed CheckStatus.FAIL to "inventory field yok — ItemApi.Page.al güncel mi?"
                CheckStatus.PASS to "inventory field döner (${first.optString("no")}=${first.optDouble("inventory")})"
            }

            // 5. BinContentApi (yeni page 72097)
            timed("bin_contents") {
                if (!hasToken) return@timed CheckStatus.SKIP to "Token gerek"
                val r = BcApi.get(context, "binContents?\$top=1")
                if (r.ok) CheckStatus.PASS to "binContents endpoint çalışıyor"
                else CheckStatus.FAIL to "HTTP ${r.httpCode} — DOPSWHS BinContent API publish edildi mi?"
            }

            // 6. LP templates (build dropdown bağımlılığı)
            timed("lp_templates") {
                if (!hasToken) return@timed CheckStatus.SKIP to "Token gerek"
                val r = BcApi.get(context, "licensePlateTemplates?\$top=10&\$select=code")
                val codes = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
                when {
                    !r.ok -> CheckStatus.FAIL to "HTTP ${r.httpCode}"
                    codes.isEmpty() -> CheckStatus.FAIL to "Hiç LP template yok — Setup gerekli"
                    else -> CheckStatus.PASS to "${codes.size} template (${codes.first().optString("code")}...)"
                }
            }

            // 7. Quality module (qualityOrders availability)
            timed("quality_orders") {
                if (!hasToken) return@timed CheckStatus.SKIP to "Token gerek"
                val r = BcApi.get(context, "qualityOrders?\$top=1")
                if (r.ok) CheckStatus.PASS to "qualityOrders endpoint çalışıyor"
                else CheckStatus.FAIL to "HTTP ${r.httpCode}"
            }

            // 8. Default printer SharedPreferences read
            timed("default_printer") {
                val printer = com.dynops.bcwms.feature.getDefaultPrinter(context)
                if (printer.isBlank()) CheckStatus.SKIP to "Default printer atanmadı (Yazıcılar ekranından seçin)"
                else CheckStatus.PASS to "Default: $printer"
            }

            // 9. ScanBus event dispatch (in-process round-trip)
            timed("scan_bus") {
                val received = withTimeoutOrNull(500) {
                    coroutineScope {
                        // UNDISPATCHED async subscribe edilir ANCAK suspending
                        // first() çağrısında parking eder; sonra emit + await.
                        val deferred = async(start = CoroutineStart.UNDISPATCHED) {
                            ScanBus.events.first()
                        }
                        delay(20)
                        ScanBus.emit(ScanEvent(raw = "SELF_TEST_PROBE", symbology = "TEST"))
                        deferred.await()
                    }
                }
                if (received?.raw == "SELF_TEST_PROBE") CheckStatus.PASS to "ScanBus emit + collect OK"
                else CheckStatus.FAIL to "Bus event alınmadı (DataWedge wiring kontrolü)"
            }

            // 10. Token freshness (basic me-call)
            timed("token_age") {
                if (!hasToken) return@timed CheckStatus.SKIP to "Token gerek"
                val r = BcApi.get(context, "licensePlates?\$top=1")
                if (r.httpCode == 401) CheckStatus.FAIL to "Token süresi dolmuş — yeniden giriş yapın"
                else if (r.ok) CheckStatus.PASS to "Token geçerli (HTTP ${r.httpCode})"
                else CheckStatus.SKIP to "Belirsiz (HTTP ${r.httpCode})"
            }

            running = false
        }
    }

    val summary = results.fold(Triple(0, 0, 0)) { acc, r ->
        when (r.status) {
            CheckStatus.PASS -> acc.copy(first = acc.first + 1)
            CheckStatus.FAIL -> acc.copy(second = acc.second + 1)
            CheckStatus.SKIP -> acc.copy(third = acc.third + 1)
            else -> acc
        }
    }
    val total = results.size

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Card(
            Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(
                containerColor = when {
                    running -> Color(0xFFE3F2FD)
                    summary.second > 0 -> Color(0xFFFFEBEE)
                    summary.first == total - summary.third && summary.first > 0 -> Color(0xFFE8F5E9)
                    else -> Color(0xFFF5F5F5)
                },
            ),
        ) {
            Column(Modifier.padding(14.dp)) {
                Text("Sistem Sağlığı", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                Text("Mobil app + BC + Print Bridge + ScanBus integration probe'ları", fontSize = 12.sp, color = Color.Gray)
                Spacer(Modifier.height(8.dp))
                Text(
                    "${summary.first} ✅  ·  ${summary.second} ❌  ·  ${summary.third} ⏭  ·  ${total - summary.first - summary.second - summary.third} ⏳",
                    fontWeight = FontWeight.Medium,
                    fontSize = 14.sp,
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { runAll() }, enabled = !running, modifier = Modifier.weight(1f)) {
                Text(if (running) "Çalışıyor…" else "▶︎ Tümünü Çalıştır", fontWeight = FontWeight.Bold)
            }
            OutlinedButton(
                onClick = { results = initialChecks() },
                enabled = !running,
                modifier = Modifier.weight(1f),
            ) { Text("Sıfırla") }
        }
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(results) { r -> CheckRow(r) }
        }
    }
}

@Composable
private fun CheckRow(r: CheckResult) {
    val (icon, color) = when (r.status) {
        CheckStatus.PASS -> "✅" to Color(0xFF2E7D32)
        CheckStatus.FAIL -> "❌" to Color(0xFFC62828)
        CheckStatus.SKIP -> "⏭" to Color(0xFF6A6A6A)
        CheckStatus.RUNNING -> "⏳" to Color(0xFF1565C0)
        CheckStatus.PENDING -> "·" to Color(0xFFBDBDBD)
    }
    Card(Modifier.fillMaxWidth()) {
        Row(
            Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(icon, fontSize = 18.sp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(r.title, fontWeight = FontWeight.Medium, fontSize = 14.sp, color = color)
                if (r.message.isNotBlank()) {
                    Text(r.message, fontSize = 11.sp, color = Color.Gray)
                }
            }
            if (r.durationMs > 0) Text("${r.durationMs}ms", fontSize = 10.sp, color = Color.Gray)
        }
    }
}

private fun initialChecks(): List<CheckResult> = listOf(
    CheckResult("token", "BC token saklanmış mı?", CheckStatus.PENDING),
    CheckResult("bc_warehouse", "warehouse/v2.0 API ulaşılabilir mi?", CheckStatus.PENDING),
    CheckResult("bc_standard", "Standart items fallback çalışıyor mu?", CheckStatus.PENDING),
    CheckResult("item_inventory", "ItemApi inventory FlowField calc çalışıyor mu?", CheckStatus.PENDING),
    CheckResult("bin_contents", "BinContentApi (page 72097) çalışıyor mu?", CheckStatus.PENDING),
    CheckResult("lp_templates", "LP templates seed edilmiş mi?", CheckStatus.PENDING),
    CheckResult("quality_orders", "qualityOrders API çalışıyor mu?", CheckStatus.PENDING),
    CheckResult("default_printer", "Default printer atanmış mı?", CheckStatus.PENDING),
    CheckResult("scan_bus", "ScanBus emit + collect çalışıyor mu?", CheckStatus.PENDING),
    CheckResult("token_age", "Token süresi geçerli mi?", CheckStatus.PENDING),
)
