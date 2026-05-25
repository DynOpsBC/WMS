package com.dynops.bcwms.sync

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class SyncWorker(
  appContext: Context,
  params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
  override suspend fun doWork(): Result = Result.success()

  companion object {
    const val EXPEDITED_WORK_NAME = "bcwms-expedited-sync"
  }
}

