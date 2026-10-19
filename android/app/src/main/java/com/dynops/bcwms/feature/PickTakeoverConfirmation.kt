package com.dynops.bcwms.feature

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import kotlinx.coroutines.CompletableDeferred

private data class PickTakeoverRequest(val no: String, val owner: String, val answer: CompletableDeferred<Boolean>)

@Composable
internal fun rememberPickTakeoverConfirmation(): suspend (String, String) -> Boolean {
    var pending by remember { mutableStateOf<PickTakeoverRequest?>(null) }
    DisposableEffect(Unit) {
        onDispose { pending?.answer?.complete(false) }
    }
    pending?.let { request ->
        AlertDialog(
            onDismissRequest = { request.answer.complete(false) },
            title = { Text("Belgeyi devralmak istediğinize emin misiniz?") },
            text = { Text("${request.no} belgesi ${request.owner} kullanıcısına atanmış. Onaylarsanız BC'deki atama sizin terminal kullanıcınıza değişecek. Önceki kullanıcı bu belgede çalışmaya devam edemeyecek.") },
            confirmButton = { TextButton(onClick = { request.answer.complete(true) }) { Text("Evet, Bana Ata") } },
            dismissButton = { TextButton(onClick = { request.answer.complete(false) }) { Text("Vazgeç") } },
        )
    }
    return { no, owner ->
        if (pending != null) false
        else {
            val request = PickTakeoverRequest(no, owner, CompletableDeferred())
            pending = request
            try { request.answer.await() } finally { if (pending === request) pending = null }
        }
    }
}
