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

/** EMU/DKÇ (15 Eyl 2026): LP labels follow the LP template design; BADE keeps its MTE flow. */
internal fun usesTemplateLpLabels(flavor: String): Boolean = !flavor.equals("bade", ignoreCase = true)

/**
 * List / bulk print: with template labels every LP (filled or empty) prints its
 * template label (BC picks pallet/carton/box/sack and the copies); otherwise
 * the BADE MTE / QR document routing.
 */
internal fun lpListPrintRoute(templateLabels: Boolean, lineCount: Int, labelPrinter: String, documentPrinter: String): LpPrintRoute =
    if (templateLabels) LpPrintRoute("printLabel", mtePrinterCode(labelPrinter, documentPrinter))
    else bulkLpPrintRoute(lineCount, labelPrinter, documentPrinter)

internal data class PullDocumentType(val enumName: String, val title: String)

/** Document types the terminal can pull LP lines from (BC enum "DOPSWHS Assigned Doc Type"). */
internal val PULL_DOCUMENT_TYPES: List<PullDocumentType> = listOf(
    PullDocumentType("SalesOrder", "Satış Siparişi"),
    PullDocumentType("PurchaseOrder", "Satınalma Siparişi"),
    PullDocumentType("TransferOrder", "Transfer Siparişi"),
    PullDocumentType("WhseReceipt", "Ambar Mal Kabul"),
    PullDocumentType("WhseShipment", "Ambar Sevkiyat"),
    PullDocumentType("WhsePick", "Toplama Belgesi"),
    PullDocumentType("WhsePutaway", "Yerleştirme Belgesi"),
    PullDocumentType("WhseMovement", "Ambar Hareketi"),
    PullDocumentType("PostedSalesShipment", "Kayıtlı Satış Sevki"),
    PullDocumentType("PostedPurchaseReceipt", "Kayıtlı Alış İrsaliyesi"),
    PullDocumentType("PostedWhseReceipt", "Kayıtlı Ambar Mal Kabul"),
    PullDocumentType("PostedWhseShipment", "Kayıtlı Ambar Sevkiyat"),
    PullDocumentType("PostedTransferShipment", "Kayıtlı Transfer Sevki"),
    PullDocumentType("PostedTransferReceipt", "Kayıtlı Transfer Alımı"),
)

/** A scanned document barcode (RE…, SH…, PI…, %S%…, %PO%…) selects the matching pull type. */
internal fun pullDocumentTypeForBarcode(docType: String?): PullDocumentType? {
    val enumName = when (docType) {
        "receipt" -> "WhseReceipt"
        "shipment" -> "WhseShipment"
        "pick" -> "WhsePick"
        "putaway" -> "WhsePutaway"
        "movement" -> "WhseMovement"
        "salesOrder" -> "SalesOrder"
        "purchaseOrder" -> "PurchaseOrder"
        "transferOrder" -> "TransferOrder"
        else -> return null
    }
    return PULL_DOCUMENT_TYPES.firstOrNull { it.enumName == enumName }
}

/** Lines can only be pulled into an open LP that is not reserved by a receipt. */
internal fun canPullFromDocument(status: String, pendingReceiptNo: String): Boolean =
    status.equals("Open", ignoreCase = true) && pendingReceiptNo.isBlank()

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

internal fun validPartialUseInput(quantity: Double?, lineNo: Int?, maximumQuantity: Double): Boolean =
    quantity != null && quantity > 0.0 && quantity <= maximumQuantity && lineNo != null && lineNo > 0

internal data class LpPartialAction(
    val apiValue: String,
    val label: String,
    val help: String,
)

internal val lpPartialActions = listOf(
    LpPartialAction(
        apiValue = "CreateNewLP",
        label = "Kalanı yeni LP'ye ayır",
        help = "Girilen miktar bu LP'de kalır; kalan miktar yeni bir LP'ye aktarılır.",
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
    val source = "Kaynak giriş: #${result.sourceEntryNo}."
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
