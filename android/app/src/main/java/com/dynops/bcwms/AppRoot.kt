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
                Screen.LicensePlates -> LicensePlatesScreen()
                Screen.ItemInquiry -> ItemInquiryScreen()
                Screen.BinInquiry -> BinInquiryScreen()
                Screen.Receiving -> DocumentListScreen("receipts", "Mal Kabul Belgeleri", "Açık mal kabul belgesi yok.")
                Screen.Picking -> DocumentListScreen("picks", "Toplama Belgeleri", "Açık toplama belgesi yok.")
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
private fun LicensePlatesScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val r = BcApi.getWithStandardFallback(context, "licensePlates?\$top=50&\$select=no,status,locationCode,binCode,templateCode,sscc")
            loading = false
            if (r.ok) {
                rows = BcApi.parseValueArray(r.body)
                status = if (rows.isEmpty()) "EMPTY: License Plate kaydı bulunamadı (HTTP ${r.httpCode})." else "PASS: ${rows.size} LP yüklendi (HTTP ${r.httpCode})."
            } else status = "EMPTY: License Plate servisi yanıt vermedi (HTTP ${r.httpCode})."
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(8.dp))
            Button(onClick = {
                scope.launch {
                    loading = true; status = "Yeni LP oluşturuluyor..."
                    val generatedNo = "MOB-${SimpleDateFormat("HHmmss", Locale.US).format(Date())}"
                    var r = BcApi.post(context, "licensePlates",
                        """{"templateCode":"CARTON-S","locationCode":"SILVER","binCode":"S-1-01"}""")
                    if (!r.ok) {
                        r = BcApi.post(context, "licensePlates",
                            """{"no":"$generatedNo","templateCode":"CARTON-S","locationCode":"SILVER","binCode":"S-1-01"}""")
                    }
                    loading = false
                    status = if (r.ok) "PASS: Yeni LP oluşturuldu (HTTP ${r.httpCode})." else "EMPTY: LP oluşturma BC tarafından reddedildi (HTTP ${r.httpCode})."
                    if (r.ok) load()
                }
            }, enabled = !loading) { Text("➕ Yeni LP") }
        }
        Spacer(Modifier.height(4.dp))
        Text(status, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { lp ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(lp.optString("no"), fontWeight = FontWeight.Bold)
                        Text("Status: ${lp.optString("status")} · ${lp.optString("templateCode")}", fontSize = 12.sp)
                        Text("Bin: ${lp.optString("locationCode")}/${lp.optString("binCode")}", fontSize = 12.sp, color = Color.Gray)
                        if (lp.optString("sscc").isNotBlank())
                            Text("SSCC: ${lp.optString("sscc")}", fontSize = 11.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) {
                item { EmptyState("License Plate kaydı bulunamadı.") }
            }
        }
    }
}

@Composable
private fun ItemInquiryScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("1896-S") }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("1896-S için sorgulayın.") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Sorgulanıyor..."
            val customFilter = if (query.isBlank()) "\$top=10" else "\$filter=no eq '$query'&\$top=10"
            val standardFilter = if (query.isBlank()) "\$top=10" else "\$filter=number eq '$query'&\$top=10"
            val r = BcApi.getWithStandardFallback(context, "items?$customFilter", "items?$standardFilter")
            loading = false
            if (r.ok) {
                rows = BcApi.parseValueArray(r.body)
                status = if (rows.isEmpty()) "EMPTY: '${query}' için item bulunamadı (HTTP ${r.httpCode})." else "PASS: ${rows.size} item bulundu (HTTP ${r.httpCode})."
            } else {
                rows = emptyList()
                status = "EMPTY: Item sorgusu başarısız oldu (HTTP ${r.httpCode})."
            }
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        OutlinedTextField(value = query, onValueChange = { query = it }, label = { Text("Item No (örn 1896-S)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
        Spacer(Modifier.height(8.dp))
        Button(enabled = !loading, onClick = { load() }) { Text(if (loading) "..." else "🔎 Sorgula") }
        Spacer(Modifier.height(12.dp))
        Text(status, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { item ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(firstValue(item, "no", "number", "itemNo"), fontWeight = FontWeight.Bold)
                        Text(firstValue(item, "description", "displayName"), fontSize = 13.sp)
                        Text("Base UoM: ${firstValue(item, "baseUnitOfMeasure", "baseUoM", "unitOfMeasureCode")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) {
                item { EmptyState("Item sonucu yok. Arama terimini kontrol edin.") }
            }
        }
    }
}

@Composable
private fun BinInquiryScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("SILVER") }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("SILVER lokasyonu için sorgulayın.") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val filter = if (query.isBlank()) "locationCode eq 'SILVER'" else "locationCode eq '$query'"
            var r = BcApi.getWithStandardFallback(context, "bins?\$filter=$filter&\$top=20", "bins?\$filter=$filter&\$top=20")
            if (!r.ok && query.isNotBlank()) {
                r = BcApi.getWithStandardFallback(context, "bins?\$filter=code eq '$query'&\$top=20", "bins?\$filter=code eq '$query'&\$top=20")
            }
            loading = false
            if (r.ok) {
                rows = BcApi.parseValueArray(r.body)
                status = if (rows.isEmpty()) "EMPTY: Bin bulunamadı (HTTP ${r.httpCode})." else "PASS: ${rows.size} bin yüklendi (HTTP ${r.httpCode})."
            } else {
                rows = emptyList()
                status = "EMPTY: Bin servisi filtre ile veri döndürmedi (HTTP ${r.httpCode})."
            }
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        OutlinedTextField(value = query, onValueChange = { query = it }, label = { Text("Location Code veya Bin Code") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
        Spacer(Modifier.height(8.dp))
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔎 Sorgula") }
        Spacer(Modifier.height(8.dp))
        Text(status, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { bin ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(firstValue(bin, "code", "no", "binCode"), fontWeight = FontWeight.Bold)
                        Text("Location: ${firstValue(bin, "locationCode")}", fontSize = 12.sp)
                        Text("Zone: ${firstValue(bin, "zoneCode")} · Type: ${firstValue(bin, "binTypeCode")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) {
                item { EmptyState("Bin sonucu yok. SILVER lokasyonu varsayılan filtre olarak kullanılır.") }
            }
        }
    }
}

@Composable
private fun DocumentListScreen(entitySet: String, title: String, emptyMessage: String) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val r = BcApi.getWithStandardFallback(context, "$entitySet?\$top=20")
            loading = false
            if (r.ok) {
                rows = BcApi.parseValueArray(r.body)
                status = if (rows.isEmpty()) "EMPTY: $emptyMessage (HTTP ${r.httpCode})." else "PASS: ${rows.size} kayıt yüklendi (HTTP ${r.httpCode})."
            } else {
                rows = emptyList()
                status = "EMPTY: $title servisi veri döndürmedi (HTTP ${r.httpCode})."
            }
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Text(title, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(8.dp))
        Text(status, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { doc ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(firstValue(doc, "no", "number", "documentNo"), fontWeight = FontWeight.Bold)
                        Text("Status: ${firstValue(doc, "status", "warehouseStatus")}", fontSize = 12.sp)
                        Text("Location: ${firstValue(doc, "locationCode")} · Source: ${firstValue(doc, "sourceNo", "sourceDocumentNo")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) {
                item { EmptyState(emptyMessage) }
            }
        }
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
