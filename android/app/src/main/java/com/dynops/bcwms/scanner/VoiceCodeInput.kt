package com.dynops.bcwms.scanner

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberUpdatedState
import java.util.Locale

/**
 * Turns a Turkish spoken code into the code a label would carry.
 * "a be tire sıfır bir" -> "AB-01", "raf on iki" is not a code and is kept.
 * Item and bin inquiries search exact numbers, so spoken words must become
 * letters and digits. Phrases that do not look like a code are returned
 * trimmed, unchanged, so the operator still sees what was heard.
 */
object VoiceCodeNormalizer {
    private val tr = Locale.forLanguageTag("tr-TR")
    private val digits = mapOf(
        "sıfır" to 0, "bir" to 1, "iki" to 2, "üç" to 3, "dört" to 4,
        "beş" to 5, "altı" to 6, "yedi" to 7, "sekiz" to 8, "dokuz" to 9,
    )
    private val tens = mapOf(
        "on" to 10, "yirmi" to 20, "otuz" to 30, "kırk" to 40, "elli" to 50,
        "altmış" to 60, "yetmiş" to 70, "seksen" to 80, "doksan" to 90,
    )
    private val letters = mapOf(
        "a" to "A", "be" to "B", "ce" to "C", "çe" to "Ç", "de" to "D", "e" to "E",
        "fe" to "F", "ge" to "G", "he" to "H", "ı" to "I", "i" to "I", "je" to "J",
        "ke" to "K", "ka" to "K", "le" to "L", "me" to "M", "ne" to "N", "o" to "O",
        "ö" to "Ö", "pe" to "P", "re" to "R", "se" to "S", "şe" to "Ş", "te" to "T",
        "u" to "U", "ü" to "Ü", "ve" to "V", "ye" to "Y", "ze" to "Z",
        "kü" to "Q", "iks" to "X", "dabılyu" to "W", "dablyu" to "W",
    )
    private val separators = mapOf(
        "tire" to "-", "çizgi" to "-", "nokta" to ".", "bölü" to "/", "slash" to "/",
    )
    private val alnum = Regex("^[\\p{L}\\p{N}._/-]+$")

    fun normalize(spoken: String): String {
        val raw = spoken.trim()
        val tokens = raw.lowercase(tr).split(Regex("\\s+")).filter { it.isNotBlank() }
        if (tokens.isEmpty()) return ""
        val out = StringBuilder()
        var i = 0
        while (i < tokens.size) {
            val t = tokens[i]
            val next = tokens.getOrNull(i + 1)
            when {
                t == "kısa" && next == "çizgi" -> { out.append('-'); i++ }
                t == "alt" && next == "çizgi" -> { out.append('_'); i++ }
                t == "eğik" && next == "çizgi" -> { out.append('/'); i++ }
                t in tens -> {
                    val unit = next?.let { digits[it] }
                    if (unit != null && unit > 0) { out.append(tens.getValue(t) + unit); i++ }
                    else out.append(tens.getValue(t))
                }
                t in digits -> out.append(digits.getValue(t))
                t in separators -> out.append(separators.getValue(t))
                t in letters -> out.append(letters.getValue(t))
                // The recognizer often already writes digits or short codes.
                alnum.matches(t) && (t.any(Char::isDigit) || t.length <= 3) ->
                    out.append(t.uppercase(Locale.ROOT))
                else -> return raw // A name or sentence: not a code.
            }
            i++
        }
        return out.toString()
    }
}

/**
 * Opens the system speech screen in Turkish. The system screen records the
 * audio itself, so the app needs no microphone permission. Devices without a
 * speech service (some Zebra images) report [onUnavailable].
 */
@Composable
fun rememberVoiceCodeLauncher(onCode: (String) -> Unit, onUnavailable: () -> Unit): () -> Unit {
    val currentOnCode = rememberUpdatedState(onCode)
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode != Activity.RESULT_OK) return@rememberLauncherForActivityResult
        val heard = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull().orEmpty()
        val code = VoiceCodeNormalizer.normalize(heard)
        if (code.isNotBlank()) currentOnCode.value(code)
    }
    return {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "tr-TR")
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Kodu söyleyin. Örnek: a be tire sıfır bir")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try { launcher.launch(intent) } catch (_: ActivityNotFoundException) { onUnavailable() }
    }
}
