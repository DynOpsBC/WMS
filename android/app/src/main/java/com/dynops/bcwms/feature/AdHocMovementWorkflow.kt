package com.dynops.bcwms.feature

import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.BarcodeKind

internal enum class AdHocProductInputRoute {
    ProductMutation,
    LicensePlateWorkflow,
    Invalid,
}

internal data class AdHocProductInputDecision(
    val route: AdHocProductInputRoute,
    val value: String,
)

/**
 * The legacy "Product" form must never turn an LP barcode into an ad-hoc item
 * journal request with an empty item number. LPs have their own atomic
 * transfer/move-to-bin contract, so detecting one here only changes workflow;
 * it never produces a stock mutation by itself.
 */
internal fun decideAdHocProductInput(raw: String): AdHocProductInputDecision {
    val resolved = BarcodeIntentResolver.resolve(raw)
    return when (resolved.kind) {
        BarcodeKind.Lp -> AdHocProductInputDecision(
            route = AdHocProductInputRoute.LicensePlateWorkflow,
            value = resolved.value.trim(),
        )

        BarcodeKind.Item -> AdHocProductInputDecision(
            route = AdHocProductInputRoute.ProductMutation,
            value = resolved.itemNo?.trim().orEmpty().ifBlank { resolved.value.trim() },
        )

        else -> AdHocProductInputDecision(
            route = AdHocProductInputRoute.Invalid,
            value = resolved.value.trim(),
        )
    }
}

// ---------------------------------------------------------------------------
// Kitoko (22 Eki 2026): "ad hoc'ta bir yere tıklamadan direkt okutabileyim".
// Ekran düzeyinde tek ScanBus dinleyicisi okutmayı o anki adıma yönlendirir;
// operatör alana dokunmadan kaynak raf → LP (ya da ürün) → hedef okutur.
// ---------------------------------------------------------------------------

/** Ekran düzeyi okutma yönlendirmesi yalnız Kitoko'da; BADE/EMU alan odaklı kalır. */
internal fun adHocScreenScanRouting(flavor: String = com.dynops.bcwms.BuildConfig.FLAVOR): Boolean =
    flavor.equals("kitoko", ignoreCase = true)

internal enum class AdHocLpStep { SourceBin, Lp, Target }

internal fun adHocLpStep(fromBin: String, lpLoaded: Boolean): AdHocLpStep = when {
    lpLoaded -> AdHocLpStep.Target
    fromBin.isBlank() -> AdHocLpStep.SourceBin
    else -> AdHocLpStep.Lp
}

internal sealed interface AdHocLpScan {
    /** Kaynak raf okutuldu: raftaki LP'ler listelenir. */
    data class SourceBin(val bin: String) : AdHocLpScan
    /** LP (LP No ya da SSCC) okutuldu: içerik yüklenir; kaynak raf boşsa LP'nin rafı kullanılır. */
    data class Lp(val ref: LpScanRef) : AdHocLpScan
    /** LP adımında LP olmayan okutma: başka raf mı ürün mü, sunucuda doğrulanır. */
    data class BinOrItem(val value: String, val itemNo: String, val lotNo: String) : AdHocLpScan
    /** Hedef (LP ya da raf) okutuldu. */
    data class Target(val value: String, val isSscc: Boolean) : AdHocLpScan
    data class Rejected(val message: String) : AdHocLpScan
}

internal fun routeAdHocLpScan(raw: String, step: AdHocLpStep): AdHocLpScan {
    val resolved = BarcodeIntentResolver.resolve(raw)
    val lp = lpScanRef(raw)
    val value = resolved.value.trim()
    if (value.isBlank()) return AdHocLpScan.Rejected("Okunan barkod boş. Yeniden okutun.")
    if (resolved.kind == BarcodeKind.Document)
        return AdHocLpScan.Rejected("Belge barkodu bu ekranda kullanılmaz. Raf, LP ya da hedef okutun.")
    return when (step) {
        AdHocLpStep.SourceBin -> if (lp != null) AdHocLpScan.Lp(lp) else AdHocLpScan.SourceBin(value)
        AdHocLpStep.Lp -> if (lp != null) AdHocLpScan.Lp(lp) else AdHocLpScan.BinOrItem(
            value = value,
            itemNo = resolved.itemNo?.trim().orEmpty().ifBlank { value },
            lotNo = resolved.lotNo?.trim().orEmpty(),
        )
        AdHocLpStep.Target -> when (lp) {
            is LpScanRef.BySscc -> AdHocLpScan.Target(lp.value, isSscc = true)
            is LpScanRef.ByNo -> AdHocLpScan.Target(lp.value, isSscc = false)
            null -> AdHocLpScan.Target(value, isSscc = false)
        }
    }
}

internal enum class AdHocProductStep { SourceBin, Item, TargetBin, Lot }

internal fun adHocProductStep(fromBin: String, itemOrLp: String, toBin: String): AdHocProductStep = when {
    fromBin.isBlank() -> AdHocProductStep.SourceBin
    itemOrLp.isBlank() -> AdHocProductStep.Item
    toBin.isBlank() -> AdHocProductStep.TargetBin
    else -> AdHocProductStep.Lot
}

internal sealed interface AdHocProductScan {
    data class SourceBin(val bin: String) : AdHocProductScan
    data class Item(val itemNo: String, val lotNo: String) : AdHocProductScan
    data class OpenLp(val lpNo: String) : AdHocProductScan
    data class TargetBin(val bin: String) : AdHocProductScan
    data class Lot(val lotNo: String) : AdHocProductScan
    data class Rejected(val message: String) : AdHocProductScan
}

internal fun routeAdHocProductScan(raw: String, step: AdHocProductStep): AdHocProductScan {
    val resolved = BarcodeIntentResolver.resolve(raw)
    val value = resolved.value.trim()
    if (value.isBlank()) return AdHocProductScan.Rejected("Okunan barkod boş. Yeniden okutun.")
    if (resolved.kind == BarcodeKind.Document)
        return AdHocProductScan.Rejected("Belge barkodu bu ekranda kullanılmaz.")
    val isLp = resolved.kind == BarcodeKind.Lp
    return when (step) {
        AdHocProductStep.SourceBin ->
            if (isLp) AdHocProductScan.OpenLp(value) else AdHocProductScan.SourceBin(value)
        AdHocProductStep.Item -> {
            val decision = decideAdHocProductInput(raw)
            when (decision.route) {
                AdHocProductInputRoute.LicensePlateWorkflow -> AdHocProductScan.OpenLp(decision.value)
                AdHocProductInputRoute.ProductMutation -> AdHocProductScan.Item(decision.value, resolved.lotNo?.trim().orEmpty())
                AdHocProductInputRoute.Invalid -> AdHocProductScan.Rejected("Bu adımda ürün veya LP barkodu okutun.")
            }
        }
        AdHocProductStep.TargetBin ->
            if (isLp) AdHocProductScan.Rejected("Hedef olarak raf okutun. LP taşımak için “LP ile” modunu kullanın.")
            else AdHocProductScan.TargetBin(value)
        AdHocProductStep.Lot -> AdHocProductScan.Lot(resolved.lotNo?.trim().orEmpty().ifBlank { value })
    }
}

/** Adım başlığında gösterilen "şimdi ne okutulacak" ipucu. */
internal fun adHocLpStepHint(step: AdHocLpStep): String = when (step) {
    AdHocLpStep.SourceBin -> "Okutun: kaynak raf (ya da doğrudan LP)"
    AdHocLpStep.Lp -> "Okutun: LP (ya da başka raf / ürün)"
    AdHocLpStep.Target -> "Okutun: hedef raf ya da hedef LP"
}

internal fun adHocProductStepHint(step: AdHocProductStep): String = when (step) {
    AdHocProductStep.SourceBin -> "Okutun: kaynak raf"
    AdHocProductStep.Item -> "Okutun: ürün (LP okutulursa LP moduna geçer)"
    AdHocProductStep.TargetBin -> "Okutun: hedef raf"
    AdHocProductStep.Lot -> "Okutun: lot (lot izlemeli üründe) ya da miktarı girip onaylayın"
}

/** Lokasyonlar arası LP taşıma seçeneği yalnız Kitoko'da (BC 1.14.3.18 moveToLocation). */
internal fun adHocLocationMoveOffered(flavor: String = com.dynops.bcwms.BuildConfig.FLAVOR): Boolean =
    flavor.equals("kitoko", ignoreCase = true)

/** Eski BC'de moveToLocation aksiyonu yok: 404 ya da "bulunamadı/does not exist" yanıtı. */
internal fun adHocLocationMoveMissing(httpCode: Int, message: String): Boolean =
    httpCode == 404 || (httpCode == 400 && (
        message.contains("moveToLocation", ignoreCase = true) &&
            (message.contains("not found", ignoreCase = true) || message.contains("does not exist", ignoreCase = true) ||
                message.contains("No HTTP resource", ignoreCase = true))
        ))

/** Onay düğmesi metni: lokasyon değişiyorsa açıkça yazar. */
internal fun adHocLpConfirmLabel(
    busy: Boolean,
    crossLocation: Boolean,
    targetLocation: String,
    target: String,
    targetIsLp: Boolean?,
): String = when {
    busy -> "Gönderiliyor..."
    crossLocation -> "✅ LP'yi ${targetLocation.trim()}${if (target.isNotBlank()) "/${target.trim()}" else ""}'e taşı (lokasyon değişir)"
    targetIsLp == true -> "✅ İçeriği $target LP'sine Aktar"
    targetIsLp == false -> "✅ LP'yi $target Rafına Taşı"
    else -> "✅ Hareketi Onayla"
}
