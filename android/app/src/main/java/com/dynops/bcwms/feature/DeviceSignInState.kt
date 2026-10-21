package com.dynops.bcwms.feature

import android.content.Context
import com.dynops.bcwms.DeviceAuth
import org.json.JSONObject

/**
 * DKÇ (21 Eki 2026): Microsoft sign-in with Authenticator approval.
 *
 * The user leaves BCWMS for the browser and Authenticator. Android may kill the
 * app in the meantime (low-memory terminals) and cuts network for background
 * apps, so the pending device code lives on disk and the code screen resumes
 * from it until the code expires.
 *
 * Only the EMU flavor uses the simple flow; other flavors keep their screens.
 */
internal fun simpleMicrosoftSignIn(flavor: String): Boolean = flavor.equals("emu", ignoreCase = true)

/** A device-code sign-in waiting for the user to finish in the browser. */
internal data class PendingDeviceSignIn(
    val deviceCode: String,
    val userCode: String,
    val verificationUri: String,
    val tenantSegment: String,
    val email: String,
    val intervalSec: Int,
    val expiresAtMs: Long,
) {
    fun remainingMs(nowMs: Long): Long = (expiresAtMs - nowMs).coerceAtLeast(0L)

    /** A code that expires within [EXPIRY_MARGIN_MS] is useless: the user cannot finish in time. */
    fun isExpired(nowMs: Long): Boolean = nowMs >= expiresAtMs - EXPIRY_MARGIN_MS

    fun pollIntervalMs(): Long = intervalSec.coerceIn(1, 60) * 1000L

    fun toDeviceCode(nowMs: Long): DeviceAuth.DeviceCode = DeviceAuth.DeviceCode(
        deviceCode = deviceCode,
        userCode = userCode,
        verificationUri = verificationUri,
        interval = intervalSec,
        expiresIn = (remainingMs(nowMs) / 1000L).toInt(),
        message = "",
        tenantSegment = tenantSegment,
    )

    fun encode(): String = JSONObject()
        .put("v", 1)
        .put("deviceCode", deviceCode)
        .put("userCode", userCode)
        .put("verificationUri", verificationUri)
        .put("tenantSegment", tenantSegment)
        .put("email", email)
        .put("intervalSec", intervalSec)
        .put("expiresAtMs", expiresAtMs)
        .toString()

    companion object {
        const val EXPIRY_MARGIN_MS = 10_000L
        const val DEFAULT_VERIFICATION_URI = "https://microsoft.com/devicelogin"

        fun from(code: DeviceAuth.DeviceCode, email: String, nowMs: Long) = PendingDeviceSignIn(
            deviceCode = code.deviceCode,
            userCode = code.userCode,
            verificationUri = code.verificationUri.ifBlank { DEFAULT_VERIFICATION_URI },
            tenantSegment = code.tenantSegment.ifBlank { "organizations" },
            email = email.trim(),
            intervalSec = code.interval.coerceAtLeast(1),
            expiresAtMs = nowMs + code.expiresIn.coerceAtLeast(0) * 1000L,
        )

        /** Null for blank, corrupt or incomplete data; never throws. */
        fun decode(raw: String?): PendingDeviceSignIn? {
            if (raw.isNullOrBlank()) return null
            return try {
                val j = JSONObject(raw)
                val pending = PendingDeviceSignIn(
                    deviceCode = j.optString("deviceCode"),
                    userCode = j.optString("userCode"),
                    verificationUri = j.optString("verificationUri").ifBlank { DEFAULT_VERIFICATION_URI },
                    tenantSegment = j.optString("tenantSegment").ifBlank { "organizations" },
                    email = j.optString("email"),
                    intervalSec = j.optInt("intervalSec", 5).coerceAtLeast(1),
                    expiresAtMs = j.optLong("expiresAtMs", 0L),
                )
                pending.takeIf { it.deviceCode.isNotBlank() && it.userCode.isNotBlank() && it.expiresAtMs > 0L }
            } catch (e: Exception) {
                null
            }
        }
    }
}

/** Raw storage of the single pending sign-in; SharedPreferences on device, a field in tests. */
internal interface PendingSignInStore {
    fun read(): String?
    fun write(raw: String?)
}

internal class PendingDeviceSignInRepository(
    private val store: PendingSignInStore,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    fun save(code: DeviceAuth.DeviceCode, email: String): PendingDeviceSignIn =
        PendingDeviceSignIn.from(code, email, clock()).also { store.write(it.encode()) }

    /** The pending sign-in to resume, or null. Expired and corrupt entries are removed. */
    fun resumable(): PendingDeviceSignIn? {
        val raw = store.read() ?: return null
        val pending = PendingDeviceSignIn.decode(raw)
        if (pending == null || pending.isExpired(clock())) {
            store.write(null)
            return null
        }
        return pending
    }

    fun clear() = store.write(null)
}

private const val SIGN_IN_PREFS = "bcwms_signin"
private const val KEY_PENDING_DEVICE_CODE = "pending_device_code"

internal fun pendingSignInRepository(context: Context): PendingDeviceSignInRepository {
    val prefs = context.applicationContext.getSharedPreferences(SIGN_IN_PREFS, Context.MODE_PRIVATE)
    return PendingDeviceSignInRepository(object : PendingSignInStore {
        override fun read(): String? = prefs.getString(KEY_PENDING_DEVICE_CODE, null)
        override fun write(raw: String?) {
            // commit(): the user is about to leave for the browser; the code must
            // already be on disk if Android kills the process right after.
            if (raw == null) prefs.edit().remove(KEY_PENDING_DEVICE_CODE).commit()
            else prefs.edit().putString(KEY_PENDING_DEVICE_CODE, raw).commit()
        }
    })
}

/** True when the connection screen must open on the waiting code (EMU only). */
internal fun hasResumableDeviceSignIn(context: Context, flavor: String): Boolean =
    simpleMicrosoftSignIn(flavor) && pendingSignInRepository(context).resumable() != null

/** What the code screen does after one poll. */
internal sealed class DevicePollStep {
    data class Wait(val nextDelayMs: Long, val offline: Boolean) : DevicePollStep()
    data class Done(val token: DeviceAuth.TokenResult.Success) : DevicePollStep()
    data class Stop(val message: String, val expired: Boolean) : DevicePollStep()
}

internal fun nextDevicePollStep(
    result: DeviceAuth.PollResult,
    currentDelayMs: Long,
    pending: PendingDeviceSignIn,
    nowMs: Long,
): DevicePollStep {
    if (result is DeviceAuth.PollResult.Success) return DevicePollStep.Done(result.token)
    if (result is DeviceAuth.PollResult.Failed)
        return DevicePollStep.Stop(result.error, expired = result.expired)
    if (pending.isExpired(nowMs)) return DevicePollStep.Stop("Kodun süresi doldu.", expired = true)
    return when (result) {
        is DeviceAuth.PollResult.Waiting ->
            DevicePollStep.Wait(if (result.slowDown) currentDelayMs + 5_000L else currentDelayMs, offline = false)
        else -> DevicePollStep.Wait(currentDelayMs, offline = true)
    }
}

/** "14:05" style remaining time for the code screen. */
internal fun formatRemaining(ms: Long): String {
    val total = (ms / 1000L).coerceAtLeast(0L)
    return "%d:%02d".format(total / 60L, total % 60L)
}

