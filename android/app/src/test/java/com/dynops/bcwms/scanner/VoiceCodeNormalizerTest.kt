package com.dynops.bcwms.scanner

import org.junit.Assert.assertEquals
import org.junit.Test

class VoiceCodeNormalizerTest {
    private fun n(s: String) = VoiceCodeNormalizer.normalize(s)

    @Test fun spokenLettersDigitsAndSeparatorsBecomeCode() {
        assertEquals("AB-01", n("a be tire sıfır bir"))
        assertEquals("AB.00102", n("A be nokta sıfır sıfır bir sıfır iki"))
        assertEquals("K-12-3", n("ke kısa çizgi on iki tire üç"))
        assertEquals("A20", n("a yirmi"))
    }

    @Test fun recognizerDigitsAndShortCodesAreUppercased() {
        assertEquals("A-01-03", n("a-01-03"))
        assertEquals("AB00102", n("ab 00102"))
        assertEquals("I10", n("ı 10"))
    }

    @Test fun sentencesStayAsHeard() {
        assertEquals("Kırmızı boya kutusu", n("  Kırmızı boya kutusu "))
        assertEquals("", n("   "))
    }
}
