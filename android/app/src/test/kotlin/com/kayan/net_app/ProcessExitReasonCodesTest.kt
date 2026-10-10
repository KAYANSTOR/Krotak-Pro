package com.kayan.net_app

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * WP-9 — تصنيف أسباب إنهاء العملية (الدليل قبل الإصلاح).
 *
 * الأرقام منسوخة من ActivityManager.REASON_* ومثبّتة هنا حتى لا يتغير
 * المعنى صامتًا. ما لا يُثبته: قراءة النظام نفسه بلا جهاز (D11).
 */
class ProcessExitReasonCodesTest {

    @Test
    fun `the reasons that explain a silent background stop are mapped`() {
        assertEquals("anr", ProcessExitReasonCodes.codeOf(6))
        assertEquals("excessive_resource_usage", ProcessExitReasonCodes.codeOf(9))
        assertEquals("low_memory", ProcessExitReasonCodes.codeOf(3))
        assertEquals("crash", ProcessExitReasonCodes.codeOf(4))
        assertEquals("user_requested", ProcessExitReasonCodes.codeOf(10))
        assertEquals("user_stopped", ProcessExitReasonCodes.codeOf(11))
        assertEquals("freezer", ProcessExitReasonCodes.codeOf(14))
    }

    @Test
    fun `unknown numbers never leak a raw code to the screen`() {
        assertEquals("unknown", ProcessExitReasonCodes.codeOf(999))
        assertEquals("unknown", ProcessExitReasonCodes.codeOf(-1))
    }

    @Test
    fun `every documented reason has a distinct stable code`() {
        val codes = (0..16).map { ProcessExitReasonCodes.codeOf(it) }
        assertEquals(codes.size, codes.toSet().size)
        codes.forEach { code ->
            assertEquals(code, code.trim())
            assertEquals(true, code.all { it.isLowerCase() || it == '_' })
        }
    }
}
