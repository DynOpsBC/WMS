package com.dynops.bcwms.feature

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.dynops.bcwms.BuildConfig
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.bcwmsStatus
import com.dynops.bcwms.ui.operatorFacingStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * In-app update channel for the sideload (APK fallback) distribution. The
 * Play Store path is handled by Play's own auto-update; this module fires
 * only when the running app was installed outside of Play (UNKNOWN_SOURCES).
 *
 * Boot:
 *   GET <base>/releases/android/latest.json
 *   { versionCode, versionName, apkUrl, sha256, releaseNotes }
 * Compare versionCode > BuildConfig.VERSION_CODE → show dialog → download
 * via DownloadManager → SHA-256 verify → ACTION_INSTALL_PACKAGE.
 */

private const val PREFS = "bcwms_prefs"
private const val KEY_UPDATE_CHECK = "bcwms.updates.enabled"
private const val KEY_LAST_PROMPTED = "bcwms.updates.lastPromptedVersionCode"

private val DEFAULT_UPDATE_BASE =
    BcApi::class.java.`package`?.let { "https://app.bcwms.dynops.com" } ?: "https://app.bcwms.dynops.com"

data class UpdateManifest(
    val versionCode: Int,
    val versionName: String,
    val apkUrl: String,
    val sha256: String,
    val releaseNotes: String,
)

private val SHA256_HEX = Regex("^[0-9a-fA-F]{64}$")
private val ALLOWED_APK_HOSTS = setOf(
    "app.bcwms.dynops.com",
    "github.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
)

fun isUpdateCheckEnabled(context: Context): Boolean =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_UPDATE_CHECK, true)

fun setUpdateCheckEnabled(context: Context, enabled: Boolean) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        .putBoolean(KEY_UPDATE_CHECK, enabled).apply()
}

/**
 * Top-level composable that polls once on first composition. Should be
 * placed near AppRoot so the dialog is reachable from any screen.
 */
@Composable
fun UpdateChecker() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var manifest by remember { mutableStateOf<UpdateManifest?>(null) }
    var downloading by remember { mutableStateOf(false) }
    var downloadProgress by remember { mutableStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        if (!isUpdateCheckEnabled(context)) return@LaunchedEffect
        try {
            val fetched = withContext(Dispatchers.IO) { fetchManifest() }
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val last = prefs.getInt(KEY_LAST_PROMPTED, 0)
            if (fetched != null && fetched.versionCode > BuildConfig.VERSION_CODE && fetched.versionCode != last) {
                manifest = fetched
            }
        } catch (_: Throwable) {
            // Network glitch — try again next boot.
        }
    }

    val m = manifest ?: return
    val status = bcwmsStatus()
    AlertDialog(
        onDismissRequest = {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putInt(KEY_LAST_PROMPTED, m.versionCode).apply()
            manifest = null
        },
        title = { Text("Yeni sürüm hazır: v${m.versionName}") },
        text = {
            Column {
                Text(
                    "Şu anki sürüm: v${BuildConfig.VERSION_NAME}. Güncellemek için 'İndir' butonuna dokunun.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (m.releaseNotes.isNotBlank()) {
                    Spacer(Modifier.height(8.dp))
                    Text(m.releaseNotes, style = MaterialTheme.typography.bodySmall)
                }
                if (downloading) {
                    Spacer(Modifier.height(8.dp))
                    LinearProgressIndicator(progress = { downloadProgress / 100f })
                    Text("%${downloadProgress}", style = MaterialTheme.typography.bodySmall)
                }
                error?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(operatorFacingStatus(it), color = status.danger)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !downloading,
                onClick = {
                    scope.launch {
                        downloading = true
                        error = null
                        try {
                            val apk = withContext(Dispatchers.IO) {
                                downloadApk(context, m, onProgress = { downloadProgress = it })
                            }
                            // SHA-256 is mandatory: manifest fetch already validates the hex
                            // form + apkUrl allowlist, but we recheck here in case the manifest
                            // was cached and the on-disk APK was tampered with.
                            if (!verifySha256(apk, m.sha256)) {
                                error = "Doğrulama başarısız — paket bozulmuş olabilir."
                                apk.delete()
                            } else {
                                installApk(context, apk)
                                manifest = null
                            }
                        } catch (t: Throwable) {
                            error = "HATA: Güncelleme indirilemedi. Bağlantıyı kontrol edip tekrar deneyin."
                        } finally {
                            downloading = false
                        }
                    }
                }
            ) { Text(if (downloading) "İndiriliyor…" else "İndir & yükle") }
        },
        dismissButton = {
            TextButton(onClick = {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putInt(KEY_LAST_PROMPTED, m.versionCode).apply()
                manifest = null
            }) { Text("Şimdi değil") }
        },
    )
}

private fun fetchManifest(): UpdateManifest? {
    val manifestUrl = URL("$DEFAULT_UPDATE_BASE/releases/android/latest.json")
    require(manifestUrl.protocol == "https") { "manifest must be served over HTTPS" }
    val conn = (manifestUrl.openConnection() as HttpURLConnection).apply {
        connectTimeout = 8_000
        readTimeout = 15_000
        requestMethod = "GET"
        setRequestProperty("Accept", "application/json")
    }
    return try {
        if (conn.responseCode / 100 != 2) return null
        val body = conn.inputStream.bufferedReader().use { it.readText() }
        val obj = org.json.JSONObject(body)
        val sha = obj.optString("sha256").trim()
        require(SHA256_HEX.matches(sha)) { "manifest sha256 missing or malformed" }
        val apkUrlRaw = obj.optString("apkUrl")
        val apkUri = Uri.parse(apkUrlRaw)
        require(apkUri.scheme == "https") { "apkUrl must be https" }
        val host = apkUri.host?.lowercase().orEmpty()
        require(host in ALLOWED_APK_HOSTS) { "apkUrl host not on allowlist: $host" }
        UpdateManifest(
            versionCode = obj.optInt("versionCode"),
            versionName = obj.optString("versionName"),
            apkUrl = apkUrlRaw,
            sha256 = sha,
            releaseNotes = obj.optString("releaseNotes"),
        )
    } catch (e: IllegalArgumentException) {
        android.util.Log.w("BcwmsUpdate", "rejecting manifest: ${e.message}")
        null
    } finally {
        conn.disconnect()
    }
}

private suspend fun downloadApk(
    context: Context,
    manifest: UpdateManifest,
    onProgress: suspend (Int) -> Unit,
): File {
    val dest = File(context.cacheDir, "updates/bcwms-${manifest.versionCode}.apk").apply {
        parentFile?.mkdirs()
        if (exists()) delete()
    }

    val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    val request = DownloadManager.Request(Uri.parse(manifest.apkUrl))
        .setTitle("BCWMS v${manifest.versionName}")
        .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, "bcwms-${manifest.versionCode}.apk")
        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        .setMimeType("application/vnd.android.package-archive")
    val id = dm.enqueue(request)

    var finishedFile: File? = null
    while (finishedFile == null) {
        val query = DownloadManager.Query().setFilterById(id)
        dm.query(query).use { cursor ->
            if (cursor != null && cursor.moveToFirst()) {
                val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                if (total > 0) onProgress(((downloaded * 100) / total).toInt())
                val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> {
                        val localUriRaw = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                        val source = File(Uri.parse(localUriRaw).path ?: error("download local uri missing"))
                        source.copyTo(dest, overwrite = true)
                        source.delete()
                        finishedFile = dest
                    }
                    DownloadManager.STATUS_FAILED -> {
                        val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                        error("Download failed (reason $reason)")
                    }
                }
            }
        }
        if (finishedFile == null) delay(700)
    }
    onProgress(100)
    return finishedFile!!
}

private fun verifySha256(file: File, expected: String): Boolean {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(8 * 1024)
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) break
            digest.update(buffer, 0, read)
        }
    }
    val computed = digest.digest().joinToString("") { "%02x".format(it) }
    return computed.equals(expected.trim(), ignoreCase = true)
}

private fun installApk(context: Context, apk: File) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apk)
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "application/vnd.android.package-archive")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    context.startActivity(intent)
}

/** Optional registry for when the app is foregrounded later — keeps surface
 *  small until needed. */
@Suppress("unused")
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        // currently a no-op; reserved for completed-download notification.
    }
}
