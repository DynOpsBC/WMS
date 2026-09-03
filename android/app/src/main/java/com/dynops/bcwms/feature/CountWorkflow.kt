package com.dynops.bcwms.feature

/**
 * A zero quantity is a valid physical count. New AL versions expose an explicit
 * counted flag; the quantity fallback keeps older in-progress sheets readable.
 */
internal fun isCountRecorded(hasExplicitFlag: Boolean, explicitFlag: Boolean, quantity: Double): Boolean =
    if (hasExplicitFlag) explicitFlag else quantity != 0.0

internal data class CountSlotLineState(
    val hasExplicitFlag: Boolean,
    val explicitlyCounted: Boolean,
    val quantity: Double,
)

/**
 * Posting is stricter than the legacy display fallback in [isCountRecorded]. A non-zero quantity
 * without the matching `countedN` flag is not proof that the active counter actually completed the
 * line in this count round. Conversely, an explicit flag makes a physical zero a valid answer.
 */
internal fun allRequiredCountLinesExplicitlyCompleted(lines: List<CountSlotLineState>): Boolean =
    lines.isNotEmpty() && lines.all { line ->
        line.hasExplicitFlag &&
            line.explicitlyCounted &&
            line.quantity.isFinite() &&
            line.quantity >= 0.0
    }

/**
 * A lotless count line must not accept a quantity when BC reports positive lot balances for the
 * same item/bin. Recording it would lose the answer to "which lot was counted?".
 */
internal fun countLineNeedsLotSelection(lineLotNo: String, positiveLotNos: List<String>): Boolean =
    lineLotNo.isBlank() && positiveLotNos.any { it.isNotBlank() }

/**
 * Plain lot numbers and plain item numbers have the same scanner shape. Prefer a lot when the
 * active count already contains it; otherwise only open the unexpected-item flow after BC confirms
 * that the scanned value is an item number.
 */
internal fun shouldResolvePlainCountBarcodeAsLot(
    hasLocalLotMatch: Boolean,
    itemExistsInBc: Boolean,
): Boolean = hasLocalLotMatch || !itemExistsInBc

internal data class CountDocumentActions(
    val canGenerateLines: Boolean,
    val canStartRecount: Boolean,
    val canPost: Boolean,
)

internal data class CountSlotAssignment(val slot: Int, val userId: String)

internal fun assignedCountSlotsForOperator(
    assignments: List<CountSlotAssignment>,
    currentUserId: String,
    adminTestSession: Boolean,
): List<Int> {
    val configured = assignments
        .filter { it.slot in 1..3 && it.userId.isNotBlank() }
        .distinctBy { it.slot }
    if (configured.isEmpty()) return listOf(1) // Eski belgeler için geriye uyumluluk.
    if (adminTestSession) return configured.map { it.slot }.sorted()
    if (currentUserId.isBlank()) return emptyList()
    return configured
        .filter { it.userId.equals(currentUserId, ignoreCase = true) }
        .map { it.slot }
        .sorted()
}

internal fun countDocumentIsMutable(status: String): Boolean =
    !status.equals("Posted", ignoreCase = true)

/**
 * Posting is fail-closed: a partial/paged line load must never be posted as a complete count.
 */
internal fun countDocumentActions(
    lineCount: Int,
    busy: Boolean,
    linesComplete: Boolean,
    headerLoaded: Boolean,
    activeSlotComplete: Boolean,
    status: String = "InProgress",
    activeSlotAssigned: Boolean = true,
    hasRecountRequired: Boolean = false,
): CountDocumentActions {
    val ready = !busy && linesComplete && headerLoaded && countDocumentIsMutable(status) && activeSlotAssigned
    return CountDocumentActions(
        canGenerateLines = ready && lineCount == 0,
        canStartRecount = ready && lineCount > 0,
        canPost = ready && lineCount > 0 && activeSlotComplete && !hasRecountRequired,
    )
}

internal data class SequentialWriteProgress(
    val total: Int,
    val succeeded: Int,
) {
    val complete: Boolean get() = total > 0 && succeeded == total
    val partial: Boolean get() = succeeded in 1 until total
}

/**
 * Client-side multi-line writes are not transactional. Normalise their progress so callers never
 * describe a partially persisted result as complete and can force a server reload/reconciliation.
 */
internal fun sequentialWriteProgress(total: Int, succeeded: Int): SequentialWriteProgress =
    SequentialWriteProgress(
        total = total.coerceAtLeast(0),
        succeeded = succeeded.coerceAtLeast(0),
    )

/**
 * Terminal posting is a BC-side setup decision (DOPSWHS Setup). The countSheets entity exposes it as
 * the read-only `terminalPostAllowed` field. An AL package that predates the field keeps the old
 * behaviour (posting allowed) so an app upgrade never silently hides the button on older tenants;
 * call sites pass `header.has("terminalPostAllowed")` / `header.optBoolean("terminalPostAllowed")`.
 */
internal fun terminalCountPostAllowed(hasFlag: Boolean, flag: Boolean): Boolean = if (!hasFlag) true else flag

/** Operatöre gösterilen bilgi: sayım onayı ve stok hareketi terminalde değil Business Central'de yapılır. */
internal const val COUNT_POSTED_IN_BC_NOTE = "Sayım Business Central'de onaylanıp stoklara işlenir."

/** completeCounter başarı mesajı; terminalden işleme kapalıysa operatöre nerede işleneceğini söyler. */
internal fun countRoundSavedMessage(slot: Int, terminalPostAllowed: Boolean): String =
    if (terminalPostAllowed) "TAMAM: $slot. sayım turu kaydedildi; stok hareketi oluşturulmadı"
    else "TAMAM: $slot. sayım turu kaydedildi. $COUNT_POSTED_IN_BC_NOTE"

/**
 * The persistent explanation line is shown once the active round is locked and the terminal cannot
 * post; it is suppressed while the status box already carries the same sentence (right after saving)
 * so the operator never reads it twice on one screen.
 */
internal fun showsCountPostedInBcNote(
    terminalPostAllowed: Boolean,
    activeSlotSaved: Boolean,
    documentStatus: String,
    currentStatusText: String,
): Boolean = !terminalPostAllowed && activeSlotSaved && countDocumentIsMutable(documentStatus) &&
    !currentStatusText.contains(COUNT_POSTED_IN_BC_NOTE)

internal data class CountPrimaryButtonState(
    val label: String,
    val enabled: Boolean,
    val opensPostConfirm: Boolean,
)

/**
 * Classic count bottom-bar primary button. Before the active round is saved it is the "save round"
 * button. After saving it becomes "post" only when the terminal may post; otherwise it turns into an
 * inert "round saved" marker that never opens the post confirmation, whatever the other flags say.
 */
internal fun classicCountPrimaryButtonState(
    interactive: Boolean,
    activeSlotSaved: Boolean,
    allRequiredSaved: Boolean,
    canPost: Boolean,
    terminalPostAllowed: Boolean,
): CountPrimaryButtonState = when {
    !activeSlotSaved -> CountPrimaryButtonState("✅ Turu Kaydet", interactive, false)
    !terminalPostAllowed -> CountPrimaryButtonState("✓ Tur Kaydedildi", false, false)
    else -> CountPrimaryButtonState("Stoklara İşle", interactive, interactive && allRequiredSaved && canPost)
}

/**
 * V2 screen: the post button is rendered only once the header has actually loaded. A null header
 * would otherwise pass the "flag absent => allowed" rule of [terminalCountPostAllowed] and flash a
 * disabled button that disappears as soon as `terminalPostAllowed=false` arrives.
 */
internal fun countV2PostButtonVisible(headerLoaded: Boolean, terminalPostAllowed: Boolean): Boolean =
    headerLoaded && terminalPostAllowed

/** Pallet numbers of the counted (lpNo-bearing) lines, trimmed and de-duplicated in line order. */
internal fun countedLpNosForLabels(lineLpNos: List<String>): List<String> =
    lineLpNos.map { it.trim() }.filter { it.isNotBlank() }.distinct()

/**
 * PostSheet rewrites LP quantities from the winning counts and the terminal reprints the pallet
 * labels right after its own post. When BC posts the sheet instead (terminal posting OFF, the
 * default) that loop never runs, so a Posted document with counted LPs offers the reprint action.
 */
internal fun showsCountedLpLabelReprint(documentStatus: String, countedLpCount: Int): Boolean =
    documentStatus.equals("Posted", ignoreCase = true) && countedLpCount > 0

/** Label print outcome; `afterPost` keeps the wording of the terminal post path. */
internal fun countedLpLabelPrintStatus(afterPost: Boolean, lpCount: Int, printFailures: Int): String {
    val prefix = if (afterPost) "Sayım kaydedildi; " else ""
    return if (printFailures == 0) "TAMAM: ${prefix}$lpCount LP etiketi güncel miktarla yazdırıldı"
    else "UYARI: ${prefix}$printFailures LP etiketi yazdırılamadı"
}
