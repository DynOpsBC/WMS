package com.dynops.bcwms.sync

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.dynops.bcwms.usecase.move.AdHocMove
import com.dynops.bcwms.usecase.putaway.ConfirmPutAwayLine

class SyncWorker(
  appContext: Context,
  params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
  override suspend fun doWork(): Result = Result.success()

  suspend fun handleOp(op: Op): Result =
    when (op) {
      is Op.BuildLp -> syncBuildLp(op)
      is Op.StopLp -> syncStopLp(op)
      is Op.AddLpLine -> syncAddLpLine(op)
      is Op.RemoveLpLine -> syncRemoveLpLine(op)
      is Op.AssignLp -> syncAssignLp(op)
      is Op.UnbuildLp -> syncUnbuildLp(op)
      is Op.TransferLp -> syncTransferLp(op)
      is Op.PrintLpLabel -> syncPrintLpLabel(op)
      is Op.UsePartialLp -> syncUsePartialLp(op)
      is Op.NestLp -> syncNestLp(op)
      is Op.UnnestLp -> syncUnnestLp(op)
      is Op.ConfirmReceiptLine -> syncConfirmReceiptLine(op)
      is Op.AssignReceipt -> syncAssignReceipt(op)
      is Op.StartReceiptLp -> syncStartReceiptLp(op)
      is Op.StopReceiptLp -> syncStopReceiptLp(op)
      is Op.ConfirmPutAwayLine -> syncConfirmPutAwayLine(op)
      is Op.RegisterPutAway -> Result.failure()
      is Op.AdHocMove -> syncAdHocMove(op)
      is Op.RegisterDirectedMove -> Result.failure()
    }

  private suspend fun syncBuildLp(op: Op.BuildLp): Result = Result.success()
  private suspend fun syncStopLp(op: Op.StopLp): Result = Result.success()
  private suspend fun syncAddLpLine(op: Op.AddLpLine): Result = Result.success()
  private suspend fun syncRemoveLpLine(op: Op.RemoveLpLine): Result = Result.success()
  private suspend fun syncAssignLp(op: Op.AssignLp): Result = Result.success()
  private suspend fun syncUnbuildLp(op: Op.UnbuildLp): Result = Result.success()
  private suspend fun syncTransferLp(op: Op.TransferLp): Result = Result.success()
  private suspend fun syncPrintLpLabel(op: Op.PrintLpLabel): Result = Result.success()
  private suspend fun syncUsePartialLp(op: Op.UsePartialLp): Result = Result.success()
  private suspend fun syncNestLp(op: Op.NestLp): Result = Result.success()
  private suspend fun syncUnnestLp(op: Op.UnnestLp): Result = Result.success()
  private suspend fun syncConfirmReceiptLine(op: Op.ConfirmReceiptLine): Result = Result.success()
  private suspend fun syncAssignReceipt(op: Op.AssignReceipt): Result = Result.success()
  private suspend fun syncStartReceiptLp(op: Op.StartReceiptLp): Result = Result.success()
  private suspend fun syncStopReceiptLp(op: Op.StopReceiptLp): Result = Result.success()
  private suspend fun syncConfirmPutAwayLine(op: Op.ConfirmPutAwayLine): Result {
    val useCase = ConfirmPutAwayLine { Result.success(Unit) }
    return useCase(op.docId, op.lineNo, op.qtyToHandle, op.binCode, op.lpNo).fold(
      onSuccess = { Result.success() },
      onFailure = { Result.retry() },
    )
  }
  private suspend fun syncAdHocMove(op: Op.AdHocMove): Result {
    val useCase = AdHocMove { Result.success(Unit) }
    return useCase(op.fromBin, op.toBin, op.itemNo, op.lpNo, op.qty).fold(
      onSuccess = { Result.success() },
      onFailure = { Result.retry() },
    )
  }

  companion object {
    const val EXPEDITED_WORK_NAME = "bcwms-expedited-sync"
  }
}
