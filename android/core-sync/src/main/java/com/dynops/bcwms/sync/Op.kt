package com.dynops.bcwms.sync

import com.dynops.bcwms.entity.AssignedDocType
import com.dynops.bcwms.entity.PartialUseAction

sealed class Op {
  data class BuildLp(val templateCode: String, val locationCode: String, val binCode: String) : Op()
  data class StopLp(val lpNo: String, val printLabel: Boolean = false) : Op()
  data class AddLpLine(val lpNo: String, val itemNo: String, val quantity: Double, val unitOfMeasure: String) : Op()
  data class RemoveLpLine(val lpNo: String, val lineNo: Int) : Op()
  data class AssignLp(val lpNo: String, val docType: AssignedDocType, val docNo: String) : Op()
  data class UnbuildLp(val lpNo: String) : Op()
  data class TransferLp(val sourceLpNo: String, val targetLpNo: String?, val lineQuantities: Map<Int, Double>) : Op()
  data class PrintLpLabel(val lpNo: String, val printerId: String? = null, val copies: Int = 1) : Op()
  data class UsePartialLp(val lpNo: String, val lineNo: Int, val quantity: Double, val action: PartialUseAction) : Op()
  data class NestLp(val childLpNo: String, val parentLpNo: String) : Op()
  data class UnnestLp(val childLpNo: String) : Op()
  data class ConfirmReceiptLine(
    val receiptNo: String,
    val lineNo: Int,
    val qtyToReceive: Double,
    val lotNo: String? = null,
    val serialNo: String? = null,
    val expiryDate: String? = null,
    val licensePlateNo: String? = null,
    val binCode: String? = null,
  ) : Op()
  data class AssignReceipt(val receiptNo: String, val userId: String) : Op()
  data class StartReceiptLp(val receiptNo: String, val lpTemplateCode: String? = null) : Op()
  data class StopReceiptLp(val receiptNo: String, val lpNo: String, val printLabel: Boolean = false) : Op()
  data class ConfirmPutAwayLine(val docId: String, val lineNo: Int, val qtyToHandle: Double, val binCode: String, val lpNo: String) : Op()
  // Online-only: standard warehouse activity registration must not be replayed offline after document state changes.
  data class RegisterPutAway(val docId: String) : Op()
  data class AdHocMove(val fromBin: String, val toBin: String, val itemNo: String, val lpNo: String, val qty: Double) : Op()
  // Online-only: directed movement registration must run against the latest Business Central activity state.
  data class RegisterDirectedMove(val docId: String) : Op()
}
