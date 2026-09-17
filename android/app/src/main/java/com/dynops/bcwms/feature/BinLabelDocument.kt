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

/** A single vector page, scaled to the printable area; defaults to ISO A3 landscape. */
internal fun printBinDocument(context: Context, bin: JSONObject) {
    val code = bin.optString("code")
    require(code.isNotBlank()) { "Raf kodu boş." }
    val snapshot = JSONObject(bin.toString())
    val name = "Bin-${bin.optString("locationCode")}-${code}".replace(Regex("[^\\p{L}\\p{N}._-]"), "_")
    val manager = context.getSystemService(Context.PRINT_SERVICE) as PrintManager
    manager.print(name, object : PrintDocumentAdapter() {
        private var attributes = PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A3.asLandscape()).build()
        override fun onLayout(oldAttributes: PrintAttributes?, newAttributes: PrintAttributes, cancellationSignal: CancellationSignal, callback: LayoutResultCallback, extras: Bundle?) {
            if (cancellationSignal.isCanceled) { callback.onLayoutCancelled(); return }
            attributes = newAttributes
            callback.onLayoutFinished(PrintDocumentInfo.Builder("$name.pdf").setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).setPageCount(1).build(), oldAttributes != newAttributes)
        }
        override fun onWrite(pages: Array<out PageRange>, destination: ParcelFileDescriptor, cancellationSignal: CancellationSignal, callback: WriteResultCallback) {
            if (cancellationSignal.isCanceled) { callback.onWriteCancelled(); return }
            if (pages.none { it.start <= 0 && it.end >= 0 }) { callback.onWriteFinished(emptyArray()); return }
            try {
                val document = PrintedPdfDocument(context, attributes)
                try {
                    val page = document.startPage(0)
                    val rect = page.info.contentRect
                    val canvas = page.canvas
                    canvas.save()
                    canvas.translate(rect.left.toFloat(), rect.top.toFloat())
                    val scale = minOf(rect.width() / 1120f, rect.height() / 770f)
                    canvas.translate((rect.width() - 1120f * scale) / 2, (rect.height() - 770f * scale) / 2)
                    canvas.scale(scale, scale)
                    drawBinLabel(canvas, snapshot)
                    canvas.restore()
                    document.finishPage(page)
                    if (cancellationSignal.isCanceled) { callback.onWriteCancelled(); return }
                    FileOutputStream(destination.fileDescriptor).use { document.writeTo(it) }
                } finally { document.close() }
                if (cancellationSignal.isCanceled) callback.onWriteCancelled() else callback.onWriteFinished(arrayOf(PageRange(0, 0)))
            } catch (e: Exception) { callback.onWriteFailed("Bin belgesi oluşturulamadı: ${e.message}") }
        }
    }, PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A3.asLandscape()).setColorMode(PrintAttributes.COLOR_MODE_MONOCHROME).setMinMargins(PrintAttributes.Margins.NO_MARGINS).build())
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
    text("RAF ETİKETİ", 48f, 84f, 40f, 590f, true)
    text(bin.optString("locationCode"), 720f, 84f, 36f, 348f, true)
    paint.color = Color.BLACK
    text(code, 48f, 295f, 135f, 735f, true)
    text("BÖLGE: ${bin.optString("zoneCode").ifBlank { "—" }}  ·  TİP: ${bin.optString("binTypeCode").ifBlank { "—" }}", 48f, 367f, 28f, 730f)
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
