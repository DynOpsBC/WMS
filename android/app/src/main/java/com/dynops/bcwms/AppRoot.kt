package com.dynops.bcwms

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.feature.*
import com.dynops.bcwms.ui.bcwmsStatus
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Cross-module navigator — Picking/PutAway/Shipment use this to deep-link
 *  to the MS Quality Management screen when an action errors out with a
 *  QC-block ("blocked by quality inspection ...") response. */
val LocalNavigator = compositionLocalOf<(Screen) -> Unit> {
    error("LocalNavigator used outside CompositionLocalProvider")
}

/** Bir modülde oluşturulan WHSE Pick'i Sevkiyat ekranında doğrudan açar. */
object WhsePickNavigation {
    private var pendingPickNo: String? = null

    fun request(pickNo: String) {
        pendingPickNo = pickNo.takeIf { it.isNotBlank() }
    }

    fun consume(): String? = pendingPickNo.also { pendingPickNo = null }
}

enum class Screen(val title: String) {
    Home("BCWMS Ana Menü"),
    Connection("Bağlantı Ayarları"),
    LicensePlates("LP (Taşıma Kabı)"),
    ItemInquiry("Ürün Sorgu"),
    BinInquiry("Bin Sorgu"),
    WhseEntries("Ambar Hareketleri"),
    Receiving("Mal Kabul"),
    Picking("Toplama"),
    Packing("Paketleme"),
    AdHocMove("Ad-Hoc Hareket"),
    Count("Sayım"),
    PutAway("Yerleştirme"),
    Shipping("Sevkiyat"),
    Production("Üretim"),
    Assembly("Montaj"),
    DirectedMove("Yönlendirilmiş Hareket"),
    Quality("Kalite Denetimi"),
    QualityMgmt("MS Kalite Yönetimi"),
    TestCenter("Test Merkezi"),
    PostingTest("Kayıt Testi"),
    Printers("Yazıcılar"),
    SelfTest("Sistem Sağlığı"),
    FieldSettings("Alan Ayarları"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot() {
    val context = androidx.compose.ui.platform.LocalContext.current
    var screen by remember { mutableStateOf(Screen.Home) }
    var connected by remember { mutableStateOf(BcApi.hasToken(context)) }

    // Kişiselleştirilmiş görünür alan tercihlerini yükle (satır kartları okur).
    com.dynops.bcwms.ui.FieldPrefs.load(context)

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
        CompositionLocalProvider(LocalNavigator provides { target -> screen = target }) {
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (screen) {
                Screen.Home -> HomeScreen(connected) { screen = it }
                Screen.Connection -> LoginFlow(onConnected = { connected = it })
                Screen.LicensePlates -> LicensePlateModule()
                Screen.ItemInquiry -> ItemInquiryModule()
                Screen.BinInquiry -> BinInquiryModule()
                Screen.WhseEntries -> WhseEntriesModule()
                Screen.Receiving -> ReceivingModule()
                Screen.Picking -> PickingModule()
                Screen.Packing -> PackingModule()
                Screen.AdHocMove -> AdHocMoveModule()
                Screen.Count -> CountModule()
                Screen.PutAway -> PutAwayModule()
                Screen.Shipping -> ShippingModule()
                Screen.Production -> ProductionModule()
                Screen.Assembly -> AssemblyModule()
                Screen.DirectedMove -> DirectedMoveModule()
                Screen.Quality -> QualityModule()
                Screen.QualityMgmt -> QualityManagementModule()
                Screen.TestCenter -> TestCenterScreen()
                Screen.PostingTest -> PostingTestModule()
                Screen.Printers -> PrintersModule()
                Screen.SelfTest -> SelfTestModule()
                Screen.FieldSettings -> FieldSettingsModule()
            }
            UpdateChecker()
        }
        }
    }
}

@Composable
private fun ConnectionBadge(connected: Boolean, onClick: () -> Unit) {
    val status = bcwmsStatus()
    val c = if (connected) status.success else status.danger
    Surface(
        shape = RoundedCornerShape(50),
        color = c.copy(alpha = 0.14f),
        modifier = Modifier.padding(end = 8.dp).clickable { onClick() }
    ) {
        Row(
            Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(c))
            Spacer(Modifier.width(6.dp))
            Text(
                if (connected) "Bağlı" else "Bağlı değil",
                color = c,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

private data class HomeTile(val screen: Screen, val emoji: String, val label: String)
private data class HomeCategory(val title: String, val accent: Color, val tiles: List<HomeTile>)

private val HomeCategories = listOf(
    HomeCategory("Gelen", Color(0xFF26A65B), listOf(
        HomeTile(Screen.Receiving, "📥", "Mal Kabul"),
        HomeTile(Screen.PutAway, "📤", "Yerleştirme"),
    )),
    HomeCategory("Giden", Color(0xFF6C5CE7), listOf(
        HomeTile(Screen.Picking, "🚚", "Toplama"),
        HomeTile(Screen.Packing, "📦", "Paketleme"),
        HomeTile(Screen.Shipping, "🚢", "Sevkiyat"),
    )),
    HomeCategory("İç Operasyon", Color(0xFF2D9CDB), listOf(
        HomeTile(Screen.LicensePlates, "📦", "LP"),
        HomeTile(Screen.AdHocMove, "↔️", "Ad-Hoc Hareket"),
        HomeTile(Screen.DirectedMove, "🧭", "Yönlendirilmiş"),
        HomeTile(Screen.Count, "🔢", "Sayım"),
    )),
    HomeCategory("Üretim", Color(0xFFE2873B), listOf(
        HomeTile(Screen.Production, "🏭", "Üretim"),
        HomeTile(Screen.Assembly, "🔧", "Montaj"),
    )),
    HomeCategory("Kalite", Color(0xFF14B8A6), listOf(
        HomeTile(Screen.Quality, "🔬", "Kalite Denetimi"),
        HomeTile(Screen.QualityMgmt, "🧫", "MS Kalite"),
    )),
    HomeCategory("Sorgu", Color(0xFF9B59B6), listOf(
        HomeTile(Screen.ItemInquiry, "🔎", "Ürün Sorgu"),
        HomeTile(Screen.BinInquiry, "📍", "Bin Sorgu"),
        HomeTile(Screen.WhseEntries, "📜", "Ambar Hareketleri"),
    )),
    HomeCategory("Sistem", Color(0xFF64748B), listOf(
        HomeTile(Screen.FieldSettings, "🧩", "Alan Ayarları"),
        HomeTile(Screen.SelfTest, "🩺", "Sistem Sağlığı"),
        HomeTile(Screen.Printers, "🖨", "Yazıcılar"),
        HomeTile(Screen.TestCenter, "🧪", "Test Merkezi"),
        HomeTile(Screen.PostingTest, "📮", "Kayıt Testi"),
        HomeTile(Screen.Connection, "⚙️", "Bağlantı"),
    )),
)

@Composable
private fun HomeScreen(connected: Boolean, onNavigate: (Screen) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    // ELOG multi-company: şirket değişince header + alt ekranlar tazelensin diye
    // basit bir sürüm sayacı. setCompany sonrası artırılır.
    var companyEpoch by remember { mutableStateOf(0) }
    var showSwitcher by remember { mutableStateOf(false) }
    // companyEpoch değişince company adını yeniden oku.
    val companyName = remember(companyEpoch) { BcApi.getCompanyName(context) }
    var accessible by remember(companyEpoch, connected) { mutableStateOf(BcApi.getAccessibleCompanies(context)) }
    // ELOG: liste boşsa (login switcher eklenmeden yapılmış / AAD-only atlama)
    // bağlıyken bir kez erişilebilir şirketleri hesapla → switcher görünür olur.
    LaunchedEffect(connected, companyEpoch) {
        if (connected && accessible.isEmpty()) {
            BcApi.refreshAccessibleCompaniesIfEmpty(context)
            accessible = BcApi.getAccessibleCompanies(context)
        }
    }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)
    ) {
        HomeHeader(
            env = BcApi.getEnvironment(context),
            company = companyName,
            connected = connected,
            canSwitch = accessible.size > 1,
            onSwitchClick = { showSwitcher = true },
        )
        if (showSwitcher) {
            CompanySwitcherSheet(
                companies = accessible,
                currentId = BcApi.getCompanyId(context),
                onDismiss = { showSwitcher = false },
                onSelect = { c ->
                    BcApi.setCompany(context, c.id, c.displayName)
                    showSwitcher = false
                    companyEpoch++   // header + aktif ekran reload tetikler
                },
            )
        }
        Spacer(Modifier.height(16.dp))

        if (!connected) {
            NotConnectedCard()
            Spacer(Modifier.height(16.dp))
        }

        HomeCategories.forEachIndexed { index, category ->
            CategorySection(category, onNavigate)
            if (index != HomeCategories.lastIndex) Spacer(Modifier.height(18.dp))
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun HomeHeader(
    env: String,
    company: String,
    connected: Boolean,
    canSwitch: Boolean = false,
    onSwitchClick: () -> Unit = {},
) {
    val status = bcwmsStatus()
    val statusColor = if (connected) status.success else Color(0xFFFF7A7A)
    Box(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(
                Brush.linearGradient(
                    listOf(MaterialTheme.colorScheme.primary, Color(0xFF4A3DB8))
                )
            )
            .padding(20.dp)
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(48.dp).clip(RoundedCornerShape(14.dp))
                        .background(Color.White.copy(alpha = 0.18f)),
                    contentAlignment = Alignment.Center
                ) { Text("📦", fontSize = 26.sp) }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        "DynOps WMS",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    // Şirket satırı: birden çok erişilebilir şirket varsa tıklanınca
                    // değiştirici açılır (▾). Tek şirkette düz metin.
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = if (canSwitch) Modifier.clip(RoundedCornerShape(6.dp)).clickable { onSwitchClick() }.padding(vertical = 2.dp) else Modifier,
                    ) {
                        Text(
                            "$env · $company",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.White.copy(alpha = 0.82f),
                            maxLines = 1
                        )
                        if (canSwitch) {
                            Spacer(Modifier.width(4.dp))
                            Text("🔀 ▾", fontSize = 11.sp, color = Color.White)
                        }
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(
                    shape = RoundedCornerShape(50),
                    color = Color.White.copy(alpha = 0.16f)
                ) {
                    Row(
                        Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(statusColor))
                        Spacer(Modifier.width(6.dp))
                        Text(
                            if (connected) "Bağlı — canlı bağlantı" else "Bağlı değil",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White
                        )
                    }
                }
                // Birden çok erişilebilir şirket varsa rozetin yanında net bir
                // "Şirket Değiştir" butonu dursun (üstteki satır tıklaması da çalışır).
                if (canSwitch) {
                    Spacer(Modifier.width(8.dp))
                    Surface(
                        shape = RoundedCornerShape(50),
                        color = Color.White.copy(alpha = 0.26f),
                        modifier = Modifier.clip(RoundedCornerShape(50)).clickable { onSwitchClick() },
                    ) {
                        Row(
                            Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("🔀", fontSize = 12.sp)
                            Spacer(Modifier.width(5.dp))
                            Text(
                                "Şirket Değiştir",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NotConnectedCard() {
    val warn = bcwmsStatus().warning
    Card(
        colors = CardDefaults.cardColors(containerColor = warn.copy(alpha = 0.12f)),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("⚠️", fontSize = 20.sp)
            Spacer(Modifier.width(10.dp))
            Text(
                "Henüz bağlanmadınız. ⚙️ Bağlantı'dan giriş yapın.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
    }
}

/**
 * ELOG: aynı ortamdaki farklı BC şirketleri (BADE / BS / ...) arasında login
 * yapmadan geçiş. Yalnız operatörün erişebildiği şirketler listelenir. Seçim
 * BcApi.setCompany'yi çağırır; sonraki tüm API çağrıları yeni şirkete gider.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CompanySwitcherSheet(
    companies: List<BcApi.Company>,
    currentId: String,
    onDismiss: () -> Unit,
    onSelect: (BcApi.Company) -> Unit,
) {
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss) {
        Text("Şirket Seç", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text(
            "Erişebildiğiniz şirketler. Seçince tüm belgeler o şirketten gelir.",
            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(12.dp))
        companies.forEach { c ->
            val selected = c.id.equals(currentId, ignoreCase = true)
            Card(
                onClick = { if (!selected) onSelect(c) },
                modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                    else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
                ),
                shape = RoundedCornerShape(12.dp),
            ) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (selected) "🏢" else "🏭", fontSize = 20.sp)
                    Spacer(Modifier.width(12.dp))
                    Text(c.displayName, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                    if (selected) Text("● Aktif", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun CategorySection(category: HomeCategory, onNavigate: (Screen) -> Unit) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(width = 4.dp, height = 16.dp).clip(RoundedCornerShape(2.dp)).background(category.accent))
            Spacer(Modifier.width(8.dp))
            Text(
                category.title.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.height(10.dp))
        val rows = category.tiles.chunked(2)
        rows.forEachIndexed { index, rowTiles ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                rowTiles.forEach { tile ->
                    HomeTileCard(tile, category.accent, Modifier.weight(1f), onNavigate)
                }
                if (rowTiles.size == 1) Spacer(Modifier.weight(1f))
            }
            if (index != rows.lastIndex) Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun HomeTileCard(
    tile: HomeTile,
    accent: Color,
    modifier: Modifier,
    onNavigate: (Screen) -> Unit
) {
    Card(
        onClick = { onNavigate(tile.screen) },
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp, pressedElevation = 8.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)),
        modifier = modifier.height(112.dp)
    ) {
        Column(
            Modifier.fillMaxSize().padding(12.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                Modifier.size(50.dp).clip(RoundedCornerShape(15.dp)).background(accent.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) { Text(tile.emoji, fontSize = 26.sp) }
            Spacer(Modifier.height(10.dp))
            Text(
                tile.label,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
                maxLines = 2
            )
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
        Text("Azure AD Erişim Belirteci", fontWeight = FontWeight.Bold)
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
                status = if (rows.isEmpty()) "BOŞ: Test run bulunamadı (HTTP ${r.httpCode})." else "TAMAM: ${rows.size} Test Run (HTTP ${r.httpCode})."
            } else status = "BOŞ: Test Center servisi yanıt vermedi (HTTP ${r.httpCode})."
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
                        Text("Durum: ${com.dynops.bcwms.feature.bcStatusLabelTr(run.optString("status"))}", fontSize = 12.sp)
                        Text(
                            "Geçen: ${run.optInt("passed")}/${run.optInt("totalCases")} · Kalan: ${run.optInt("failed")} · ${run.optDouble("durationSec")}s",
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
