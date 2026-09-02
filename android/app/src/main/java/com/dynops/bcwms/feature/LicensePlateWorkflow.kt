package com.dynops.bcwms.feature

internal fun bulkLpPrintAction(lineCount: Int): String =
    if (lineCount > 0) "printPalletLabels" else "printLabel"

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
