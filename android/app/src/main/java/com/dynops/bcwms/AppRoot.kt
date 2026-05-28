package com.dynops.bcwms

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.feature.*
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class Screen(val title: String) {
    Home("BCWMS Ana Menü"),
    Connection("Bağlantı Ayarları"),
    LicensePlates("License Plate"),
    ItemInquiry("Item Inquiry"),
    BinInquiry("Bin Inquiry"),
    Receiving("Mal Kabul"),
    Picking("Toplama"),
    AdHocMove("Ad-Hoc Hareket"),
    Count("Sayım"),
    PutAway("Put-Away"),
    Shipping("Sevkiyat"),
    Production("Üretim"),
    Assembly("Montaj"),
    TestCenter("Test Center"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot() {
    val context = androidx.compose.ui.platform.LocalContext.current
    var screen by remember { mutableStateOf(Screen.Home) }
    var connected by remember { mutableStateOf(BcApi.hasToken(context)) }

    LaunchedEffect(Unit) {
        if (BcApi.hasToken(context)) {
            connected = BcApi.testConnection(context).ok
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(screen.title) },
                navigationIcon = {
                    if (screen != Screen.Home) {
                        TextButton(onClick = { screen = Screen.Home }) { Text("‹ Menü") }
                    }
                },
                actions = {
                    ConnectionBadge(connected) { screen = Screen.Connection }
                }
            )
        }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (screen) {
                Screen.Home -> HomeScreen(connected) { screen = it }
                Screen.Connection -> ConnectionScreen(onConnected = { connected = it })
                Screen.LicensePlates -> LicensePlateModule()
                Screen.ItemInquiry -> ItemInquiryModule()
                Screen.BinInquiry -> BinInquiryModule()
                Screen.Receiving -> ReceivingModule()
                Screen.Picking -> PickingModule()
                Screen.AdHocMove -> AdHocMoveModule()
                Screen.Count -> CountModule()
                Screen.PutAway -> ComingSoonScreen("Put-Away", "Yerleştirme belge listesi → suggest bin → Register. BC putaways API'si yayınlandığında aktif olur.")
                Screen.Shipping -> ComingSoonScreen("Sevkiyat", "Released sevkiyat belgesi → Post + packing slip. BC shipments API'si yayınlandığında aktif olur.")
                Screen.Production -> ComingSoonScreen("Üretim", "Sarfiyat (consume) + Output (→ yeni LP). productionConsumption/productionOutput action'ları Faz 2'de bağlanacak.")
                Screen.Assembly -> ComingSoonScreen("Montaj", "Montaj emri → bileşenler → Post. assemblies API mevcut, akış Faz 2'de tamamlanacak.")
                Screen.TestCenter -> TestCenterScreen()
            }
        }
    }
}

@Composable
private fun ConnectionBadge(connected: Boolean, onClick: () -> Unit) {
    TextButton(onClick = onClick) {
        Text(
            if (connected) "🟢 Bağlı" else "🔴 Bağlı değil",
            color = if (connected) Color(0xFF2E7D32) else Color(0xFFC62828),
            fontSize = 13.sp
        )
    }
}

data class Tile(val screen: Screen, val emoji: String, val label: String)

@Composable
private fun HomeScreen(connected: Boolean, onNavigate: (Screen) -> Unit) {
    val tiles = listOf(
        Tile(Screen.LicensePlates, "📦", "License Plate"),
        Tile(Screen.Receiving, "📥", "Mal Kabul"),
        Tile(Screen.Picking, "🚚", "Toplama"),
        Tile(Screen.AdHocMove, "↔️", "Ad-Hoc Hareket"),
        Tile(Screen.Count, "🔢", "Sayım"),
        Tile(Screen.PutAway, "📤", "Put-Away"),
        Tile(Screen.Shipping, "🚢", "Sevkiyat"),
        Tile(Screen.Production, "🏭", "Üretim"),
        Tile(Screen.Assembly, "🔧", "Montaj"),
        Tile(Screen.ItemInquiry, "🔎", "Item Inquiry"),
        Tile(Screen.BinInquiry, "📍", "Bin Inquiry"),
        Tile(Screen.TestCenter, "🧪", "Test Center"),
        Tile(Screen.Connection, "⚙️", "Bağlantı"),
    )
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text("DynOps Warehouse Management", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text(
            "BC Sandbox: ${BcApi.ENVIRONMENT} / ${BcApi.COMPANY_NAME}",
            fontSize = 12.sp, color = Color.Gray
        )
        Spacer(Modifier.height(8.dp))
        if (!connected) {
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0))) {
                Text(
                    "⚠️ Henüz bağlanmadınız. Önce ⚙️ Bağlantı'dan token girin.",
                    Modifier.padding(12.dp), fontSize = 13.sp
                )
            }
            Spacer(Modifier.height(8.dp))
        }
        LazyVerticalGrid(columns = GridCells.Fixed(2), verticalArrangement = Arrangement.spacedBy(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            gridItems(tiles) { t ->
                Card(
                    modifier = Modifier.fillMaxWidth().height(110.dp),
                    onClick = { onNavigate(t.screen) },
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Column(
                        Modifier.fillMaxSize().padding(16.dp),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(t.emoji, fontSize = 32.sp)
                        Spacer(Modifier.height(8.dp))
                        Text(t.label, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    }
}

@Composable
private fun ConnectionScreen(onConnected: (Boolean) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var token by remember { mutableStateOf(BcApi.getToken(context)) }
    var status by remember { mutableStateOf(if (BcApi.hasToken(context)) "Token kayıtlı. Test edebilirsiniz." else "Token girin.") }
    var testing by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState())) {
        Text("Azure AD Access Token", fontWeight = FontWeight.Bold)
        Text(
            "Mac terminal: az account get-access-token --resource https://api.businesscentral.dynamics.com --query accessToken -o tsv | pbcopy → sonra buraya Cmd+V",
            fontSize = 11.sp, color = Color.Gray
        )
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = token, onValueChange = { token = it },
            label = { Text("Token") },
            modifier = Modifier.fillMaxWidth(),
            visualTransformation = PasswordVisualTransformation(),
            maxLines = 4
        )
        Spacer(Modifier.height(12.dp))
        Row {
            Button(enabled = token.isNotBlank() && !testing, onClick = {
                BcApi.saveToken(context, token)
                scope.launch {
                    testing = true
                    status = "Test ediliyor..."
                    val r = BcApi.testConnection(context)
                    testing = false
                    if (r.ok) {
                        status = "🟢 Bağlantı başarılı (HTTP ${r.httpCode}). Token kaydedildi."
                        onConnected(true)
                    } else {
                        status = "🔴 Başarısız (HTTP ${r.httpCode}): ${r.body.take(200)}"
                        onConnected(false)
                    }
                }
            }) { Text(if (testing) "..." else "Kaydet + Test Et") }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = {
                BcApi.clearToken(context); token = ""; status = "Token temizlendi."; onConnected(false)
            }) { Text("Temizle") }
        }
        Spacer(Modifier.height(16.dp))
        Card { Text(status, Modifier.padding(12.dp), fontSize = 13.sp) }
    }
}
@Composable
private fun TestCenterScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Test Run'lar yükleniyor..."
            val r = BcApi.getWithStandardFallback(context, "testRuns?\$top=20&\$select=runNo,status,totalCases,passed,failed,passRate,durationSec")
            loading = false
            if (r.ok) {
                rows = BcApi.parseValueArray(r.body)
                status = if (rows.isEmpty()) "EMPTY: Test run bulunamadı (HTTP ${r.httpCode})." else "PASS: ${rows.size} Test Run (HTTP ${r.httpCode})."
            } else status = "EMPTY: Test Center servisi yanıt vermedi (HTTP ${r.httpCode})."
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(4.dp))
        Text(status, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { run ->
                val passRate = run.optInt("passRate")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(run.optString("runNo"), fontWeight = FontWeight.Bold)
                            Text(
                                "%$passRate",
                                color = if (passRate >= 100) Color(0xFF2E7D32) else Color(0xFFEF6C00),
                                fontWeight = FontWeight.Bold
                            )
                        }
                        Text("Status: ${run.optString("status")}", fontSize = 12.sp)
                        Text(
                            "Passed: ${run.optInt("passed")}/${run.optInt("totalCases")} · Failed: ${run.optInt("failed")} · ${run.optDouble("durationSec")}s",
                            fontSize = 12.sp, color = Color.Gray
                        )
                    }
                }
            }
            if (rows.isEmpty() && !loading) {
                item { EmptyState("TR-000001..TR-000004 test run kayıtları bulunamadı.") }
            }
        }
    }
}

private fun firstValue(obj: JSONObject, vararg keys: String): String {
    for (key in keys) {
        val value = obj.optString(key)
        if (value.isNotBlank() && value != "null") return value
    }
    return "-"
}

@Composable
private fun EmptyState(message: String) {
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFF5F5F5))
    ) {
        Text(message, Modifier.padding(16.dp), fontSize = 13.sp, color = Color(0xFF616161))
    }
}
