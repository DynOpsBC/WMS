package com.dynops.bcwms.feature

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.*
import android.print.pdf.PrintedPdfDocument
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import org.json.JSONObject
import java.io.FileOutputStream

internal fun binLabelMatrix(code: String, format: BarcodeFormat) = MultiFormatWriter().encode(
    code, format, 0, 0, mapOf(EncodeHintType.CHARACTER_SET to "UTF-8", EncodeHintType.MARGIN to 12),
)

/** Prints one bin per full A4 page (DKÇ, 17 Eyl 2026: an area's bins in one go). */
internal fun printBinDocument(context: Context, bin: JSONObject) =
    printBinDocuments(context, listOf(bin), "Bin-${bin.optString("locationCode")}-${bin.optString("code")}")

/**
 * One vector page per bin, each scaled to the printable area of an A4 sheet in
 * landscape. The operator hangs the sheet as it is; nothing is cut.
 */
internal fun printBinDocuments(context: Context, bins: List<JSONObject>, documentName: String) {
    require(bins.isNotEmpty()) { "Yazdırılacak raf yok." }
    val snapshots = bins.map { JSONObject(it.toString()) }
    require(snapshots.all { it.optString("code").isNotBlank() }) { "Raf kodu boş." }
    val name = documentName.replace(Regex("[^\\p{L}\\p{N}._-]"), "_").ifBlank { "Raf-Etiketleri" }
    val manager = context.getSystemService(Context.PRINT_SERVICE) as PrintManager
    manager.print(name, object : PrintDocumentAdapter() {
        private var attributes = PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4.asLandscape()).build()
        override fun onLayout(oldAttributes: PrintAttributes?, newAttributes: PrintAttributes, cancellationSignal: CancellationSignal, callback: LayoutResultCallback, extras: Bundle?) {
            if (cancellationSignal.isCanceled) { callback.onLayoutCancelled(); return }
            attributes = newAttributes
            callback.onLayoutFinished(
                PrintDocumentInfo.Builder("$name.pdf")
                    .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                    .setPageCount(snapshots.size)
                    .build(),
                oldAttributes != newAttributes,
            )
        }
        override fun onWrite(pages: Array<out PageRange>, destination: ParcelFileDescriptor, cancellationSignal: CancellationSignal, callback: WriteResultCallback) {
            if (cancellationSignal.isCanceled) { callback.onWriteCancelled(); return }
            val wanted = snapshots.indices.filter { index -> pages.any { it.start <= index && it.end >= index } }
            if (wanted.isEmpty()) { callback.onWriteFinished(emptyArray()); return }
            try {
                val document = PrintedPdfDocument(context, attributes)
                try {
                    for ((written, index) in wanted.withIndex()) {
                        if (cancellationSignal.isCanceled) { callback.onWriteCancelled(); return }
                        val page = document.startPage(written)
                        val rect = page.info.contentRect
                        val canvas = page.canvas
                        canvas.save()
                        canvas.translate(rect.left.toFloat(), rect.top.toFloat())
                        val scale = minOf(rect.width() / 1120f, rect.height() / 770f)
                        canvas.translate((rect.width() - 1120f * scale) / 2, (rect.height() - 770f * scale) / 2)
                        canvas.scale(scale, scale)
                        drawBinLabel(canvas, snapshots[index])
                        canvas.restore()
                        document.finishPage(page)
                    }
                    if (cancellationSignal.isCanceled) { callback.onWriteCancelled(); return }
                    FileOutputStream(destination.fileDescriptor).use { document.writeTo(it) }
                } finally { document.close() }
                if (cancellationSignal.isCanceled) callback.onWriteCancelled()
                else callback.onWriteFinished(wanted.map { PageRange(it, it) }.toTypedArray())
            } catch (e: Exception) { callback.onWriteFailed("Raf belgesi oluşturulamadı: ${e.message}") }
        }
    }, PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4.asLandscape()).setColorMode(PrintAttributes.COLOR_MODE_MONOCHROME).setMinMargins(PrintAttributes.Margins.NO_MARGINS).build())
}

internal fun drawBinLabel(canvas: Canvas, bin: JSONObject) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK }
    fun text(value: String, x: Float, y: Float, size: Float, width: Float, bold: Boolean = false) {
        paint.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        paint.textSize = size
        if (paint.measureText(value) > width) paint.textSize *= width / paint.measureText(value)
        canvas.drawText(value, x, y, paint)
    }
    val code = bin.optString("code")
    canvas.drawColor(Color.WHITE)
    paint.style = Paint.Style.STROKE; paint.strokeWidth = 3f
    canvas.drawRect(24f, 24f, 1096f, 746f, paint)
    paint.style = Paint.Style.FILL
    canvas.drawRect(24f, 24f, 1096f, 115f, paint)
    paint.color = Color.WHITE
    // DKÇ 17 Eyl: the area must be readable from the aisle, so its name (not
    // just the code) fills the band and the bin code stays the largest text.
    val zoneName = bin.optString("zoneDescription").ifBlank { bin.optString("zoneCode") }
    text(zoneName.ifBlank { "RAF ETİKETİ" }, 48f, 84f, 40f, 590f, true)
    text(bin.optString("locationCode"), 720f, 84f, 36f, 348f, true)
    paint.color = Color.BLACK
    text(code, 48f, 295f, 135f, 735f, true)
    val zoneLine = listOfNotNull(
        bin.optString("zoneCode").takeIf(String::isNotBlank)?.let { "ALAN: $it" },
        bin.optString("binTypeCode").takeIf(String::isNotBlank)?.let { "TİP: $it" },
    ).joinToString("  ·  ")
    text(zoneLine, 48f, 367f, 28f, 730f)
    text(bin.optString("description"), 48f, 420f, 30f, 730f)
    fun matrix(format: BarcodeFormat, x: Float, y: Float, width: Float, height: Float) {
        val bits = binLabelMatrix(code, format)
        paint.isAntiAlias = false
        for (row in 0 until bits.height) for (col in 0 until bits.width) if (bits[col, row]) {
            canvas.drawRect(x + col * width / bits.width, y + row * height / bits.height,
                x + (col + 1) * width / bits.width, y + (row + 1) * height / bits.height, paint)
        }
        paint.isAntiAlias = true
    }
    matrix(BarcodeFormat.QR_CODE, 806f, 155f, 260f, 260f)
    text("QR = RAF KODU", 824f, 441f, 20f, 240f)
    // Code 128 supports ASCII. Unicode codes remain fully scannable via the UTF-8 QR.
    if (code.all { it.code in 32..126 } && code.length <= 80) {
        matrix(BarcodeFormat.CODE_128, 48f, 480f, 1020f, 165f)
    }
    text(code, 48f, 703f, 38f, 1020f, true)
}
