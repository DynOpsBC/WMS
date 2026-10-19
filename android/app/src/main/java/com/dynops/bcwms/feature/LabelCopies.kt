package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

/** DKÇ (17 Eyl 2026): operators choose how many item / bin labels to print. */
internal const val LABEL_COPIES_MAX = 99

/** Business Central and the Windows print agent accept 1..10 copies per job. */
internal const val LABEL_COPIES_PER_JOB = 10

internal fun parseLabelCopies(text: String): Int? =
    text.trim().toIntOrNull()?.takeIf { it in 1..LABEL_COPIES_MAX }

/** Splits a requested label count into print jobs of at most [LABEL_COPIES_PER_JOB] copies. */
internal fun labelCopyBatches(total: Int): List<Int> {
    val count = total.coerceIn(1, LABEL_COPIES_MAX)
    return List((count + LABEL_COPIES_PER_JOB - 1) / LABEL_COPIES_PER_JOB) { index ->
        minOf(LABEL_COPIES_PER_JOB, count - index * LABEL_COPIES_PER_JOB)
    }
}

/**
 * Location lookup rows from the BCWMS locations API (code, name,
 * useAsInTransit) or, when the installed BC extension predates it, from the
 * standard API (code, displayName). In-transit locations are left out.
 */
internal fun inquiryLocationChoices(rows: List<JSONObject>): List<Pair<String, String>> =
    rows.filter { !it.optBoolean("useAsInTransit", false) }
        .map { it.optString("code").trim() to it.optString("name").ifBlank { it.optString("displayName") }.trim() }
        .filter { it.first.isNotBlank() }
        .distinctBy { it.first.uppercase() }

@Composable
internal fun LabelCopiesField(
    value: String,
    onValueChange: (String) -> Unit,
    enabled: Boolean = true,
    label: String = "Etiket adedi",
    modifier: Modifier = Modifier,
) {
    val current = parseLabelCopies(value)
    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
            OutlinedButton(
                onClick = { onValueChange(((current ?: 1) - 1).coerceAtLeast(1).toString()) },
                enabled = enabled && (current ?: 1) > 1,
                contentPadding = PaddingValues(0.dp),
                modifier = Modifier.size(48.dp),
            ) { Text("−", fontSize = 22.sp, fontWeight = FontWeight.Bold) }
            Spacer(Modifier.width(6.dp))
            OutlinedTextField(
                value = value,
                onValueChange = { text -> onValueChange(text.filter(Char::isDigit).take(2)) },
                enabled = enabled,
                singleLine = true,
                isError = current == null,
                textStyle = MaterialTheme.typography.titleMedium.copy(textAlign = TextAlign.Center, fontWeight = FontWeight.Bold),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.width(84.dp),
            )
            Spacer(Modifier.width(6.dp))
            OutlinedButton(
                onClick = { onValueChange(((current ?: 0) + 1).coerceAtMost(LABEL_COPIES_MAX).toString()) },
                enabled = enabled && (current ?: 0) < LABEL_COPIES_MAX,
                contentPadding = PaddingValues(0.dp),
                modifier = Modifier.size(48.dp),
            ) { Text("+", fontSize = 22.sp, fontWeight = FontWeight.Bold) }
        }
        if (current == null) Text(
            "1 ile $LABEL_COPIES_MAX arasında bir adet girin.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
        )
    }
}

/**
 * DKÇ (17 Eyl 2026): "konumlardan alanlara, alandan o alanın gözlerini QR
 * alıcam". Zones of a location for the label flow. The zones API arrived with
 * BC 1.14.2.7; older extensions fall back to the distinct zone codes of the
 * bins API, which carries no description.
 */
internal fun inquiryZoneChoices(rows: List<JSONObject>): List<Pair<String, String>> =
    rows.map { it.optString("code").trim() to it.optString("description").trim() }
        .filter { it.first.isNotBlank() }
        .distinctBy { it.first.uppercase() }
        .sortedBy { it.first.uppercase() }

/** A1, A2, A10 — not A1, A10, A2: digits inside a bin code sort numerically. */
internal fun sortedBinCodes(rows: List<JSONObject>): List<JSONObject> =
    rows.sortedWith(compareBy({ binSortKey(it.optString("code")) }, { it.optString("code").uppercase() }))

private fun binSortKey(code: String): String =
    Regex("\\d+|\\D+").findAll(code.uppercase()).joinToString("") { part ->
        val value = part.value
        if (value.first().isDigit()) value.padStart(9, '0') else value
    }
