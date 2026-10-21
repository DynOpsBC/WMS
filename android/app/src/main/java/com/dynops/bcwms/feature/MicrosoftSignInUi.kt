package com.dynops.bcwms.feature

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.ui.bcwmsStatus

/** Copies the sign-in code so the user only has to paste it on the Microsoft page. */
internal fun copySignInCode(context: Context, userCode: String): Boolean = runCatching {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return false
    clipboard.setPrimaryClip(ClipData.newPlainText("Microsoft giriş kodu", userCode))
    true
}.getOrDefault(false)

/**
 * Opens the Microsoft device-login page as a Custom Tab on top of BCWMS (Custom
 * Tabs protocol, no extra library). The page stays in the BCWMS task: after the
 * Authenticator approval, opening BCWMS shows the page again (for its "Devam"
 * button) and closing it returns straight to the waiting code screen. Browsers
 * without Custom Tabs ignore the extra and open the page normally.
 */
internal fun openSignInPage(context: Context, uri: String): Boolean = runCatching {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
        putExtras(Bundle().apply { putBinder("android.support.customtabs.extra.SESSION", null) })
        if (context !is Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    context.startActivity(intent)
    true
}.getOrDefault(false)

/** EMU code screen: big code, one button, short steps, live waiting state. */
@Composable
internal fun MicrosoftCodePanel(
    pending: PendingDeviceSignIn?,
    nowMs: Long,
    expired: Boolean,
    offline: Boolean,
    approved: Boolean,
    copied: Boolean,
    busy: Boolean,
    brandColor: Color,
    onCopyAndOpen: () -> Unit,
    onNewCode: () -> Unit,
    onCancel: () -> Unit,
) {
    val palette = bcwmsStatus()
    Text("Microsoft ile giriş", fontWeight = FontWeight.Bold, fontSize = 18.sp)
    Spacer(Modifier.height(12.dp))

    if (approved) {
        WaitingRow(
            title = "Giriş onaylandı",
            detail = "Bağlanılıyor, lütfen bekleyin…",
            color = palette.success,
        )
        return
    }

    if (!expired && pending != null) {
        Card(
            colors = CardDefaults.cardColors(containerColor = brandColor.copy(alpha = 0.10f)),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                Modifier.fillMaxWidth().padding(vertical = 18.dp, horizontal = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("Giriş kodunuz", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Text(
                    pending.userCode,
                    fontSize = 40.sp,
                    fontWeight = FontWeight.ExtraBold,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 3.sp,
                    color = brandColor,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    if (copied) "Kod kopyalandı ✓" else "Kod kopyalanmadı, butona basın",
                    fontSize = 12.sp,
                    color = if (copied) palette.success else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(14.dp))
        Button(
            onClick = onCopyAndOpen,
            modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp),
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = brandColor),
        ) {
            Text(
                "Kodu kopyala ve giriş sayfasını aç",
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
                textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(16.dp))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(
                "Açılan sayfada kodu yapıştırın.",
                "Hesabınızla giriş yapın.",
                "Authenticator'da onaylayın.",
                "Sayfada \"Devam\" çıkarsa basın.",
                "Bu ekrana dönün, kendiliğinden devam eder.",
            ).forEachIndexed { index, text -> StepRow(index + 1, text, brandColor) }
        }
        Spacer(Modifier.height(16.dp))
        WaitingRow(
            title = if (offline) "İnternet bekleniyor…" else "Onay bekleniyor…",
            detail = "Kalan süre ${formatRemaining(pending.remainingMs(nowMs))}",
            color = if (offline) palette.warning else brandColor,
        )
        Spacer(Modifier.height(10.dp))
        Text(
            "Kodu telefonunuzdan da girebilirsiniz: ${pending.verificationUri.removePrefix("https://").removePrefix("http://")}",
            fontSize = 11.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    } else {
        Card(
            colors = CardDefaults.cardColors(containerColor = palette.danger.copy(alpha = 0.10f)),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Kodun süresi doldu", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = palette.danger)
                Spacer(Modifier.height(4.dp))
                Text("Yeni bir kod alıp tekrar deneyin.", fontSize = 13.sp, textAlign = TextAlign.Center)
            }
        }
        Spacer(Modifier.height(14.dp))
        Button(
            onClick = onNewCode,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp),
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = brandColor),
        ) { Text(if (busy) "Kod alınıyor…" else "Yeni kod al", fontWeight = FontWeight.Bold, fontSize = 16.sp) }
    }

    Spacer(Modifier.height(8.dp))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        TextButton(onClick = onCancel, enabled = !busy) { Text("‹ Vazgeç") }
        if (!expired && pending != null)
            TextButton(onClick = onNewCode, enabled = !busy) { Text("Yeni kod al") }
    }
}

@Composable
private fun StepRow(number: Int, text: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(26.dp).clip(CircleShape).background(color.copy(alpha = 0.14f)),
            contentAlignment = Alignment.Center,
        ) { Text("$number", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = color) }
        Spacer(Modifier.width(10.dp))
        Text(text, fontSize = 14.sp)
    }
}

@Composable
private fun WaitingRow(title: String, detail: String, color: Color) {
    Card(
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.08f)),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(24.dp), color = color, strokeWidth = 3.dp)
            Spacer(Modifier.width(14.dp))
            Column {
                Text(title, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                Text(detail, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
