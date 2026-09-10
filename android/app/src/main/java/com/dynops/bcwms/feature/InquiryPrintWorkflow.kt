package com.dynops.bcwms.feature

/** Inquiry labels support ZPL printers and a PDF document-printer fallback. */
internal fun inquiryLabelPrinter(labelPrinter: String, documentPrinter: String, labelAvailable: Boolean = true): String =
    if (labelPrinter.isNotBlank() && labelAvailable) labelPrinter else documentPrinter
