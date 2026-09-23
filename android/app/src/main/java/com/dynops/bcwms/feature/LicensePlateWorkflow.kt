package com.dynops.bcwms.feature

internal const val BULK_LP_PRINT_CONCURRENCY = 3

internal fun bulkLpPrintAction(lineCount: Int): String =
    if (lineCount > 0) "printPalletLabels" else "printLabel"

/**
 * Business Central limits concurrent requests per user. Small ordered batches
 * remove the one-request-at-a-time bottleneck without flooding the tenant or
 * allowing an unbounded selection to occupy every HTTP connection.
 */
internal fun bulkLpPrintBatches(
    lpNos: List<String>,
    maxParallel: Int = BULK_LP_PRINT_CONCURRENCY,
): List<List<String>> {
    require(maxParallel > 0) { "maxParallel must be positive" }
    return lpNos.chunked(maxParallel)
}

internal data class LpPrintRoute(val action: String, val printerCode: String)

/**
 * İçerikli LP her zaman MTE ister. MTE cihazın etiket (ZPL) yazıcısına gider;
 * BC yalnız seçili yazıcı PDF belge yazıcısıysa onaylı RDLC PDF'ini üretir.
 * Etiket yazıcısı seçilmemişse belge yazıcısı, o da yoksa BC'nin cihaz-yazıcı
 * eşlemesi kullanılır. Boş taşıyıcı için ZPL/QR belge yolu korunur.
 */
internal fun bulkLpPrintRoute(lineCount: Int, labelPrinter: String, documentPrinter: String): LpPrintRoute = when {
    lineCount > 0 -> mtePrintRoute(labelPrinter, documentPrinter)
    labelPrinter.isNotBlank() -> LpPrintRoute(bulkLpPrintAction(lineCount), labelPrinter.trim())
    documentPrinter.isNotBlank() -> LpPrintRoute("printDocument", documentPrinter.trim())
    else -> LpPrintRoute(bulkLpPrintAction(lineCount), "")
}

/** Sahadaki 4x2" ZPL MTE önce etiket yazıcısını kullanır; BC formatı yazıcıdan çözer. */
internal fun mtePrinterCode(labelPrinter: String, documentPrinter: String): String =
    labelPrinter.trim().ifBlank { documentPrinter.trim() }

internal fun mtePrintRoute(labelPrinter: String, documentPrinter: String): LpPrintRoute =
    LpPrintRoute("printPalletLabels", mtePrinterCode(labelPrinter, documentPrinter))

/** Extra MTE fields the operator fills before printing (BADE report 60150 request page). */
internal data class MteOptions(
    val inspectorEmployeeNo: String = "",
    val supplierLotNo: String = "",
    val qcEmployeeNo: String = "",
    val qcApprovalDate: String = "",
)

/** JSON with only the filled fields; dates already normalised to yyyy-MM-dd. */
internal fun mteOptionsJson(options: MteOptions): String {
    val json = org.json.JSONObject()
    fun put(key: String, value: String) { if (value.isNotBlank()) json.put(key, value.trim()) }
    put("inspectorEmployeeNo", options.inspectorEmployeeNo)
    put("supplierLotNo", options.supplierLotNo)
    put("qcEmployeeNo", options.qcEmployeeNo)
    put("qcApprovalDate", options.qcApprovalDate)
    return json.toString()
}

/** Accepts dd.MM.yyyy, dd/MM/yyyy or yyyy-MM-dd; returns yyyy-MM-dd, "" for blank, null when invalid. */
internal fun normalizeMteDate(input: String): String? {
    val value = input.trim()
    if (value.isEmpty()) return ""
    Regex("""^(\d{4})-(\d{2})-(\d{2})$""").matchEntire(value)?.let { return value }
    Regex("""^(\d{1,2})[./](\d{1,2})[./](\d{4})$""").matchEntire(value)?.let { m ->
        val (d, mo, y) = m.destructured
        val day = d.toInt(); val month = mo.toInt()
        if (day !in 1..31 || month !in 1..12) return null
        return "%s-%02d-%02d".format(y, month, day)
    }
    return null
}

/**
 * The customer MTE is a PDF report: it needs the device's document printer;
 * without one BC falls back to the ZPL MTE on the label printer.
 */
internal fun mteReportPrinterCode(labelPrinter: String, documentPrinter: String): String =
    documentPrinter.trim().ifBlank { labelPrinter.trim() }

internal fun canPrintMte(linesComplete: Boolean, lineCount: Int, pendingReceiptNo: String): Boolean =
    linesComplete && lineCount > 0 && pendingReceiptNo.isBlank()

internal fun canDeleteLicensePlate(status: String, lineCount: Int): Boolean =
    lineCount == 0 && (
        status.equals("Open", ignoreCase = true) ||
            status.equals("Unbuilt", ignoreCase = true)
        )

internal fun validLpTrackingQuantity(serialTrackingRequired: Boolean, quantity: Double): Boolean =
    !serialTrackingRequired || quantity == 1.0

internal fun sourceBinBelongsToLpLocation(lpLocation: String, sourceBinLocations: List<String>): Boolean =
    lpLocation.isNotBlank() && sourceBinLocations.any { it.equals(lpLocation, ignoreCase = true) }

internal fun sourceBinLookupAllowsMove(
    pageComplete: Boolean,
    lpLocation: String,
    sourceBinLocations: List<String>,
): Boolean = pageComplete && sourceBinBelongsToLpLocation(lpLocation, sourceBinLocations)

internal fun activeLicensePlateStatus(status: String): Boolean =
    status.equals("Open", ignoreCase = true) ||
        status.equals("Built", ignoreCase = true) || status.equals("Assigned", ignoreCase = true)

internal fun lpUomOptions(baseUom: String, configuredUoms: List<String>, stockUoms: List<String>): List<String> =
    (listOf(baseUom) + configuredUoms + stockUoms)
        .map(String::trim)
        .filter(String::isNotBlank)
        .distinctBy(String::uppercase)

internal fun lpLotIsRequired(trackingRequiresLot: Boolean, availableLotCount: Int, scannedLot: String): Boolean =
    trackingRequiresLot || availableLotCount > 0 || scannedLot.isNotBlank()

internal fun canEditLicensePlate(status: String): Boolean =
    status.equals("Open", ignoreCase = true)

/**
 * A stock-built pallet may receive another product/lot before it is used or
 * assigned to a document. This is the normal mixed-pallet case: the first
 * stock row creates the physical LP, later rows remain separate LP lines.
 */
internal fun canAppendLicensePlateLine(status: String): Boolean =
    status.equals("Open", ignoreCase = true) || status.equals("Built", ignoreCase = true)

internal fun canAssignLicensePlateBin(status: String, lineCount: Int, binCode: String): Boolean =
    binCode.isBlank() && lineCount == 0 && (
        status.equals("Open", ignoreCase = true) || status.equals("Built", ignoreCase = true)
    )

internal fun shouldPatchInitialBinForLegacyServer(httpCode: Int, error: String): Boolean =
    httpCode in 400..499 && error.contains("Bin Code", ignoreCase = true) && (
        error.contains("must have a value", ignoreCase = true) ||
            error.contains("zorunlu", ignoreCase = true) ||
            error.contains("empty", ignoreCase = true) ||
            error.contains("boş", ignoreCase = true)
        )

internal fun canTransferLicensePlate(status: String, lineCount: Int): Boolean =
    status.equals("Built", ignoreCase = true) && lineCount > 0

internal fun canPartiallyUseLicensePlate(status: String, lineCount: Int): Boolean =
    status.equals("Built", ignoreCase = true) && lineCount > 0

internal fun validPartialUseInput(quantity: Double?, lineNo: Int?, maximumQuantity: Double, action: String): Boolean =
    quantity != null && quantity.isFinite() &&
        (quantity > 0.0 || (quantity == 0.0 && action == "CreateNewLP")) &&
        quantity <= maximumQuantity && lineNo != null && lineNo > 0

internal data class LpPartialAction(
    val apiValue: String,
    val label: String,
    val help: String,
)

internal val lpPartialActions = listOf(
    LpPartialAction(
        apiValue = "CreateNewLP",
        label = "Kalanı yeni LP'ye ayır",
        help = "Girilen miktar bu LP'de kalır; kalan miktar yeni bir LP'ye aktarılır. Tamamını aktarmak için 0 girin.",
    ),
    LpPartialAction(
        apiValue = "RemoveExcess",
        label = "Miktarı düzelt",
        help = "Satır miktarı girilen miktara düşürülür.",
    ),
    LpPartialAction(
        apiValue = "RemoveUsedPortion",
        label = "Kullanılan miktarı çıkar",
        help = "Girilen miktar mevcut satırdan düşülür.",
    ),
)

/** Never automatically reprint labels whose first print outcome is unknown. */
internal fun ledgerLpPrintSelection(result: LedgerBulkLpBuildResult): Set<String> = when {
    !result.printLabelsRequested -> result.createdLpNos.toSet()
    result.replayed -> emptySet()
    else -> result.failedPrintLpNos.toSet()
}

internal fun ledgerLpCompletionStatus(result: LedgerBulkLpBuildResult): String {
    val count = result.createdLpNos.size
    val sourceEntries = result.sourceEntryNos.ifEmpty { listOf(result.sourceEntryNo) }
    val source = "Kaynak giriş${if (sourceEntries.size > 1) "leri" else ""}: " +
        sourceEntries.joinToString { "#$it" } + "."
    return when {
        result.printSkippedOnReplay ->
            "UYARI: Daha önce oluşturulan $count LP doğrulandı. $source " +
                "Etiketler yeniden gönderilmedi; fiziksel etiketleri kontrol edip yalnız eksikleri seçin."
        !result.printLabelsRequested ->
            "TAMAM: $count LP kaynak girişine bağlı. $source " +
                "Etiketler henüz yazdırılmadı; LP'ler seçili, Seçilenleri Yazdır düğmesine basın."
        result.failedPrintLpNos.isNotEmpty() ->
            "UYARI: $count LP kaynak girişine bağlı. $source " +
                "${result.failedPrintLpNos.size} etiket gönderilemedi. Yalnız başarısız LP'ler seçili; Seçilenleri Yazdır ile tekrar deneyin."
        else ->
            "TAMAM: $count LP kaynak girişine bağlı ve etiketleri kuyruğa alındı. $source"
    }
}

/**
 * printMte exists from BCWMS 1.14.1.39 on. Older BC builds answer the bound action with
 * 404 (no such resource) or a 400 naming the action; then the label is still printed via
 * printPalletLabels, only without the operator's extra fields.
 */
internal fun mteFallbackToLegacy(httpCode: Int, error: String): Boolean =
    httpCode == 404 ||
        error.contains("printMte", ignoreCase = true) ||
        error.contains("No HTTP resource was found", ignoreCase = true)

/** printPalletLabels takes only printerId + copies; drop optionsJson from the printMte body. */
internal fun legacyMteBody(body: String): String {
    val src = runCatching { org.json.JSONObject(body) }.getOrDefault(org.json.JSONObject())
    return org.json.JSONObject().apply {
        put("printerId", src.optString("printerId"))
        put("copies", src.optInt("copies", 1).coerceAtLeast(1))
    }.toString()
}
