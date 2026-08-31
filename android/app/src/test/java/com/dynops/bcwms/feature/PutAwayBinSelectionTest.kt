package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PutAwayBinSelectionTest {
    @Test
    fun `ilk bin listesi tum raflari sirali yukler`() {
        // Depoda 600'den fazla raf olabiliyor; 200'lük sayfa Y bölgesinin
        // tamamını listeden düşürüyordu.
        val path = putAwayBinListPath("MERKEZDEPO")

        assertEquals(
            "bins?\$filter=locationCode eq 'MERKEZDEPO'&\$orderby=code&\$top=1000",
            path,
        )
    }

    @Test
    fun `bin aramasi lokasyonu ve kismi kodu server side filtreler`() {
        val path = putAwayExactBinPath("MERKEZDEPO", "Y.G03")

        assertEquals(
            "bins?\$filter=locationCode eq 'MERKEZDEPO' and " +
                "(code eq 'Y.G03' or startswith(code,'Y.G03'))&\$orderby=code&\$top=50",
            path,
        )
    }

    @Test
    fun `tam bin aramasi odata tirnaklarini guvenli kacirir`() {
        val path = putAwayExactBinPath("M'RK", "Y'03")

        assertTrue(path.contains("locationCode eq 'M''RK'"))
        assertTrue(path.contains("code eq 'Y''03'"))
    }

    @Test
    fun `take ve place satirlari tek mantiksal yerlestirme sayilir`() {
        val common = mapOf(
            "sourceNo" to "PO-100",
            "sourceLineNo" to 10,
            "whseDocumentNo" to "PU-100",
            "whseDocumentLineNo" to 10,
            "itemNo" to "HM.00042",
            "variantCode" to "",
            "unitOfMeasureCode" to "KG",
        )
        fun line(action: String, lineNo: Int) = JSONObject().apply {
            common.forEach { (key, value) -> put(key, value) }
            put("actionType", action)
            put("lineNo", lineNo)
        }

        assertEquals(
            1,
            logicalPutAwayMovementCount(
                listOf(line("Take", 10000), line("Place", 20000)),
            ),
        )
    }

    @Test
    fun `farkli kaynak satirlari ayri yerlestirme sayilir`() {
        fun pair(sourceLineNo: Int): List<JSONObject> = listOf("Take", "Place").mapIndexed { index, action ->
            JSONObject().apply {
                put("sourceNo", "PO-100")
                put("sourceLineNo", sourceLineNo)
                put("whseDocumentNo", "PU-100")
                put("whseDocumentLineNo", sourceLineNo)
                put("itemNo", "HM.00042")
                put("unitOfMeasureCode", "KG")
                put("actionType", action)
                put("lineNo", sourceLineNo * 1000 + index)
            }
        }

        assertEquals(2, logicalPutAwayMovementCount(pair(10) + pair(20)))
    }

    @Test
    fun `ayni urunun farkli lot ve LP satirlari ayri yerlestirme sayilir`() {
        fun pair(lotNo: String, lpNo: String, baseLineNo: Int): List<JSONObject> =
            listOf("Take", "Place").mapIndexed { index, action ->
                JSONObject().apply {
                    put("sourceNo", "PO-200")
                    put("sourceLineNo", 10)
                    put("whseDocumentNo", "PU-200")
                    put("whseDocumentLineNo", 10)
                    put("itemNo", "HM.00169")
                    put("unitOfMeasureCode", "KG")
                    put("lotNo", lotNo)
                    put("lpNo", lpNo)
                    put("actionType", action)
                    put("lineNo", baseLineNo + index)
                    put("qtyToHandle", if (lotNo == "H100795") 5 else 15)
                }
            }

        val lines = pair("H100795", "LP000063", 10000) + pair("H100796", "LP000064", 20000)

        assertEquals(2, logicalPutAwayMovementCount(lines))
    }

    @Test
    fun `register only keeps staged pair positive and clears untouched rows`() {
        fun pair(sourceLineNo: Int, baseLineNo: Int): List<JSONObject> =
            listOf("Take", "Place").mapIndexed { index, action ->
                JSONObject().apply {
                    put("sourceNo", "PO-300")
                    put("sourceLineNo", sourceLineNo)
                    put("whseDocumentNo", "PU-300")
                    put("whseDocumentLineNo", sourceLineNo)
                    put("itemNo", "ITEM-$sourceLineNo")
                    put("unitOfMeasureCode", "ADET")
                    put("actionType", action)
                    put("lineNo", baseLineNo + index)
                    put("qtyToHandle", 10)
                }
            }
        val first = pair(10, 10000)
        val second = pair(20, 20000)

        val plan = putAwayRegisterQuantityPlan(first + second, first.map { it.optInt("lineNo") }.toSet())

        assertEquals(10.0, plan[10000] ?: -1.0, 0.0)
        assertEquals(10.0, plan[10001] ?: -1.0, 0.0)
        assertEquals(0.0, plan[20000] ?: -1.0, 0.0)
        assertEquals(0.0, plan[20001] ?: -1.0, 0.0)
    }

    @Test
    fun `prepared line ids survive reload while removed rows are discarded`() {
        val current = listOf(
            JSONObject().put("lineNo", 10000),
            JSONObject().put("lineNo", 10001),
        )

        assertEquals(
            setOf(10000, 10001),
            retainExistingPutAwayStagedLineNos(setOf(10000, 10001, 90000), current),
        )
    }
}
