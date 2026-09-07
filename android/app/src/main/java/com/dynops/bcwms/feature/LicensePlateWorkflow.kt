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
 * Toplu baskı, LP kartındaki tekli "QR Etiketini Yazdır" düğmesiyle aynı
 * yazıcıya gitmeli. Cihazda ZPL etiket yazıcısı seçiliyse etiket aksiyonları;
 * yalnız PDF belge yazıcısı seçiliyse LP QR belgesi (BADE'de tekli baskı
 * çalışırken toplu baskının "Yazıcı ayarı tamamlanamadı" demesinin nedeni
 * buydu). İkisi de seçili değilse BC'deki cihaz-yazıcı eşlemesi denensin diye
 * etiket aksiyonu boş yazıcı koduyla çağrılır.
 */
internal fun bulkLpPrintRoute(lineCount: Int, labelPrinter: String, documentPrinter: String): LpPrintRoute = when {
    labelPrinter.isNotBlank() -> LpPrintRoute(bulkLpPrintAction(lineCount), labelPrinter.trim())
    documentPrinter.isNotBlank() -> LpPrintRoute("printDocument", documentPrinter.trim())
    else -> LpPrintRoute(bulkLpPrintAction(lineCount), "")
}

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
