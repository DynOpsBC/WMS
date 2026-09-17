package com.dynops.bcwms.feature

import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import org.junit.Assert.assertEquals
import org.junit.Test

class BinLabelDocumentTest {
    private fun decode(code: String, format: BarcodeFormat): String {
        val matrix = binLabelMatrix(code, format)
        val scale = 5
        val width = matrix.width * scale
        val height = if (format == BarcodeFormat.CODE_128) 150 else matrix.height * scale
        val pixels = IntArray(width * height) { i ->
            val row = if (format == BarcodeFormat.CODE_128) 0 else i / width / scale
            if (matrix[i % width / scale, row]) 0xff000000.toInt() else 0xffffffff.toInt()
        }
        return MultiFormatReader().decode(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(width, height, pixels)))).text
    }
    @Test fun `QR returns raw bin code including unicode`() {
        for (code in listOf("A.B04.13", "RAF-İ-01", "BIN'42", "A".repeat(100))) {
            assertEquals(code, decode(code, BarcodeFormat.QR_CODE))
        }
    }
    @Test fun `linear barcode returns raw bin code`() {
        for (code in listOf("A.B04.13", "BIN'42", "1234567890")) {
            assertEquals(code, decode(code, BarcodeFormat.CODE_128))
        }
    }
}
