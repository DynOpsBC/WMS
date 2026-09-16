package com.dynops.bcwms.feature

/**
 * Inquiry labels (Ürün Sorgu / Raf Sorgu) go to the device's label printer.
 *
 * 16 Eyl 2026: the device selection is the operator's decision and wins. Before,
 * a selected label printer was dropped in favour of the document printer as soon
 * as its BC record was missing or not ZPL (a freshly installed printer, a record
 * deactivated by the agent), so the terminal silently printed to an old document
 * printer. Now the document printer is used only when no label printer is
 * selected at all; a stale selection surfaces as a BC error the operator can act
 * on instead of an invisible re-route.
 */
internal fun inquiryLabelPrinter(labelPrinter: String, documentPrinter: String, labelAvailable: Boolean = true): String =
    if (labelPrinter.isNotBlank()) labelPrinter else documentPrinter

/**
 * Warning shown next to the print result when the selected label printer is not
 * a usable ZPL record in BC. The job is still sent to that printer.
 */
internal fun inquiryLabelWarning(labelPrinter: String, labelAvailable: Boolean): String =
    if (labelPrinter.isNotBlank() && !labelAvailable)
        "UYARI: $labelPrinter yazıcısı BC'de aktif ZPL kaydı olarak görünmüyor. Windows yazıcı ajanında Yazıcıları Yenile + Buluta Eşitle yapın."
    else ""
