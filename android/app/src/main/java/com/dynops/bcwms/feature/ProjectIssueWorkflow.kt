package com.dynops.bcwms.feature

import org.json.JSONObject

// Kitoko/Element4 #3338 (11 Kas 2026): Projeye Çıkış — saha iş emrine malzeme çıkışı.
// BC tarafı: BCWMSApp 1.14.3.32 (fieldWorkOrders / fieldWorkOrderLines / issueItem).
// Bu dosya ekrandan bağımsız kurallardır; birim testleri ProjectIssueWorkflowTest.

internal const val PROJECT_ISSUE_BC_MISSING = "Bu BC sürümünde Projeye Çıkış yok. BCWMSApp 1.14.3.32 kurulmalı."

internal data class FieldWorkOrder(
    val no: String,
    val projectNo: String,
    val projectTaskNo: String,
    val projectDescription: String,
    val description: String,
    val team: String,
    val plannedStart: String,
    val plannedFinish: String,
    val status: String,
    val itemLineCount: Int,
)

internal data class FieldWorkOrderLine(
    val lineNo: Int,
    val itemNo: String,
    val description: String,
    val quantity: Double,
    val actualQuantity: Double,
    val uom: String,
) {
    val remaining: Double get() = (quantity - actualQuantity).coerceAtLeast(0.0)
}

internal data class ProjectIssueRequest(
    val workOrderNo: String,
    val itemNo: String,
    val variantCode: String = "",
    val quantity: Double,
    val uom: String,
    val locationCode: String,
    val binCode: String,
    val lpNo: String,
    val lotNo: String,
    val serialNo: String,
    val userId: String,
)

internal fun parseFieldWorkOrder(o: JSONObject): FieldWorkOrder = FieldWorkOrder(
    no = o.optString("no"),
    projectNo = o.optString("projectNo"),
    projectTaskNo = o.optString("projectTaskNo"),
    projectDescription = o.optString("projectDescription"),
    description = o.optString("description"),
    team = o.optString("team"),
    plannedStart = o.optString("plannedStart").takeUnless { it == "0001-01-01" }.orEmpty(),
    plannedFinish = o.optString("plannedFinish").takeUnless { it == "0001-01-01" }.orEmpty(),
    status = o.optString("status"),
    itemLineCount = o.optInt("itemLineCount"),
)

/** Yalnız madde satırları; ekip/kaynak satırları terminalde gösterilmez. */
internal fun parseFieldWorkOrderItemLines(rows: List<JSONObject>): List<FieldWorkOrderLine> =
    rows.filter { it.optBoolean("isItem") && it.optString("no").isNotBlank() }
        .map {
            FieldWorkOrderLine(
                lineNo = it.optInt("lineNo"),
                itemNo = it.optString("no"),
                description = it.optString("description"),
                quantity = it.optDouble("quantity", 0.0),
                actualQuantity = it.optDouble("actualQuantity", 0.0),
                uom = it.optString("unitOfMeasureCode"),
            )
        }
        .sortedBy { it.lineNo }

/** Arama kutusu: iş emri no, proje no, görev, açıklama veya ekipte geçen metin. */
internal fun filterFieldWorkOrders(orders: List<FieldWorkOrder>, query: String): List<FieldWorkOrder> {
    val q = query.trim()
    if (q.isEmpty()) return orders
    return orders.filter {
        listOf(it.no, it.projectNo, it.projectTaskNo, it.description, it.projectDescription, it.team)
            .any { field -> field.contains(q, ignoreCase = true) }
    }
}

/** Kaydetmeden önce terminalde gösterilen hata; null = gönderilebilir. */
internal fun validateProjectIssue(request: ProjectIssueRequest, binMandatory: Boolean): String? = when {
    request.workOrderNo.isBlank() -> "Önce saha iş emrini seçin."
    request.locationCode.isBlank() -> "Lokasyon seçin."
    binMandatory && request.binCode.isBlank() -> "Bu lokasyon raf zorunlu: önce rafı okutun."
    request.itemNo.isBlank() -> "Ürün okutun veya listeden seçin."
    request.quantity.isNaN() || request.quantity <= 0.0 -> "Miktar 0'dan büyük olmalı."
    request.serialNo.isNotBlank() && request.quantity != 1.0 -> "Seri numaralı üründe miktar 1 olmalı."
    request.userId.isBlank() -> "Depo kullanıcısı belirlenemedi. Yeniden giriş yapın."
    else -> null
}

internal fun projectIssueBody(request: ProjectIssueRequest): String = JSONObject().apply {
    put("itemNo", request.itemNo.trim().uppercase())
    put("variantCode", request.variantCode.trim())
    put("quantity", request.quantity)
    put("unitOfMeasureCode", request.uom.trim())
    put("locationCode", request.locationCode.trim().uppercase())
    put("binCode", request.binCode.trim().uppercase())
    put("lpNo", request.lpNo.trim().uppercase())
    put("lotNo", request.lotNo.trim())
    put("serialNo", request.serialNo.trim())
    put("userId", request.userId.trim())
}.toString()

internal fun fieldWorkOrderLinesPath(workOrderNo: String): String =
    "fieldWorkOrderLines?\$filter=workOrderNo eq '${workOrderNo.replace("'", "''")}'"
