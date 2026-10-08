package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class PickLotPolicyTest {
    @Test
    fun `warehouse tracking disabled does not request or probe lots`() {
        assertEquals(PickLotInputPolicy(false, false, false),
            pickLotInputPolicy(listOf(JSONObject().put("lotRequired", false))))
    }

    @Test
    fun `warehouse tracked pick requires a lot even when stock lookup is empty`() {
        assertEquals(PickLotInputPolicy(true, true, false),
            pickLotInputPolicy(listOf(JSONObject().put("lotRequired", true))))
    }

    @Test
    fun `existing assigned lot stays required even if setup flag is false`() {
        assertEquals(PickLotInputPolicy(true, true, false), pickLotInputPolicy(listOf(
            JSONObject().put("lotRequired", false).put("lotNo", "LOT-1"))))
    }

    @Test
    fun `old packages keep stock detection for missing or null metadata`() {
        listOf(JSONObject(), JSONObject().put("lotRequired", JSONObject.NULL)).forEach {
            assertEquals(PickLotInputPolicy(false, true, true), pickLotInputPolicy(listOf(it)))
        }
    }

    @Test
    fun `null lot is not an assigned lot`() {
        assertEquals(PickLotInputPolicy(false, false, false), pickLotInputPolicy(listOf(
            JSONObject().put("lotRequired", false).put("lotNo", JSONObject.NULL))))
    }

    @Test
    fun `group requires lot when any member requires it`() {
        assertEquals(PickLotInputPolicy(true, true, false), pickLotInputPolicy(listOf(
            JSONObject().put("lotRequired", false), JSONObject().put("lotRequired", true))))
    }

    @Test
    fun `unknown group member preserves legacy stock detection`() {
        assertEquals(PickLotInputPolicy(false, true, true), pickLotInputPolicy(listOf(
            JSONObject().put("lotRequired", false), JSONObject())))
    }
}
