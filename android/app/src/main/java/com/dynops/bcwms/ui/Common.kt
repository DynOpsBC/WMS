package com.dynops.bcwms.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
        colors = CardDefaults.cardColors(containerColor = Color(0xFFF5F5F5))
    ) {
        Text(message, Modifier.padding(16.dp), fontSize = 13.sp, color = Color(0xFF616161))
    }
}

/** Status banner that colour-codes PASS / EMPTY / error text. */
@Composable
fun StatusText(status: String) {
    if (status.isBlank()) return
    val color = when {
        status.startsWith("PASS") || status.startsWith("🟢") || status.startsWith("✅") -> Color(0xFF2E7D32)
        status.startsWith("EMPTY") || status.startsWith("⚠️") -> Color(0xFFEF6C00)
        status.startsWith("HATA") || status.startsWith("🔴") || status.startsWith("❌") -> Color(0xFFC62828)
        else -> Color.Gray
    }
    Text(status, fontSize = 12.sp, color = color)
}

/** Reusable document header card. */
@Composable
fun DocHeaderCard(title: String, subtitle: String, badge: String? = null, percent: Int? = null) {
    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
        Column(Modifier.padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                badge?.let {
                    AssistChip(onClick = {}, label = { Text(it) })
                }
            }
            Text(subtitle, fontSize = 12.sp, color = Color.Gray)
            if (percent != null) {
                Spacer(Modifier.height(8.dp))
                LinearProgressIndicator(
                    progress = { (percent.coerceIn(0, 100)) / 100f },
                    modifier = Modifier.fillMaxWidth()
                )
                Text("%$percent tamamlandı", fontSize = 11.sp, color = Color.Gray)
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
