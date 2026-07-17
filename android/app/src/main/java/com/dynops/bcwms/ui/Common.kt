package com.dynops.bcwms.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

/** First non-blank value among the given keys; "-" if none. */
fun firstValue(obj: JSONObject, vararg keys: String): String {
    for (key in keys) {
        val value = obj.optString(key)
        if (value.isNotBlank() && value != "null") return value
    }
    return "-"
}

@Composable
fun EmptyState(message: String) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Text(
            message,
            Modifier.padding(16.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/** Status banner that colour-codes PASS / EMPTY / error text. */
@Composable
fun StatusText(status: String) {
    if (status.isBlank()) return
    val palette = bcwmsStatus()
    val color = when {
        status.startsWith("PASS") || status.startsWith("🟢") || status.startsWith("✅") -> palette.success
        status.startsWith("EMPTY") || status.startsWith("⚠️") -> palette.warning
        status.startsWith("HATA") || status.startsWith("🔴") || status.startsWith("❌") -> palette.danger
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(status, style = MaterialTheme.typography.bodySmall, color = color)
}

/** Reusable document header card. */
@Composable
fun DocHeaderCard(title: String, subtitle: String, badge: String? = null, percent: Int? = null) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                badge?.let {
                    Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)) {
                        Text(
                            it,
                            Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (percent != null) {
                Spacer(Modifier.height(8.dp))
                LinearProgressIndicator(
                    progress = { (percent.coerceIn(0, 100)) / 100f },
                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)),
                )
                Spacer(Modifier.height(4.dp))
                Text("%$percent tamamlandı", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Bottom action bar: a row of buttons pinned under content. */
@Composable
fun BottomActionBar(content: @Composable RowScope.() -> Unit) {
    Surface(tonalElevation = 3.dp, shadowElevation = 8.dp) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content
        )
    }
}
