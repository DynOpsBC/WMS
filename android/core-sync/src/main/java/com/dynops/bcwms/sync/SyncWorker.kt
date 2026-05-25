package com.dynops.bcwms.sync

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

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

  companion object {
    const val EXPEDITED_WORK_NAME = "bcwms-expedited-sync"
  }
}
