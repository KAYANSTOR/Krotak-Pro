package com.kayan.net_app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * اختبار JVM حقيقي لمنطق صندوق الرسائل الواردة في طبقة أندرويد.
 *
 * يخضع للاختبار نفس الصنف [SmsInboxQueue] الذي يستخدمه [SmsInboxStore] فعليًا
 * في التطبيق (`SmsReceiver` يكتب عبره، و`MainActivity` يقرّ ويؤكّد عبره)، لذلك
 * هذا ليس اختبار MethodChannel وهميًا: هو منطق الإنتاج ذاته يعمل على JVM بلا
 * جهاز ولا محاكي.
 *
 * التخزين هنا قائم في الذاكرة بدل SharedPreferences، وهي الطبقة الوحيدة التي
 * تحتاج جهازًا فعليًا (تُغطّى في device validation).
 */
class SmsInboxQueueTest {

    /** تخزين خام في الذاكرة يحاكي SharedPreferences. */
    private class MemoryStorage {
        var raw: String? = null

        fun queue() = SmsInboxQueue(
            readRaw = { raw },
            writeRaw = { raw = it },
        )
    }

    @Test
    fun `peek returns pending messages in arrival order`() {
        val storage = MemoryStorage()
        val queue = storage.queue()

        queue.append("779776919", "100", 1_000L)
        queue.append("779776920", "200", 2_000L)

        val pending = queue.peek()
        assertEquals(2, pending.size)
        assertEquals(listOf("779776919", "779776920"), pending.map { it.sender })
        assertEquals(listOf(1_000L, 2_000L), pending.map { it.timestampMillis })
        assertEquals(listOf("100", "200"), pending.map { it.body })
    }

    @Test
    fun `peek honours the requested limit without dropping anything`() {
        val storage = MemoryStorage()
        val queue = storage.queue()
        repeat(5) { index -> queue.append("sender", "body$index", index.toLong()) }

        assertEquals(2, queue.peek(limit = 2).size)
        assertEquals("body0", queue.peek(limit = 2).first().body)
        // القراءة المحدودة لا تحذف شيئًا.
        assertEquals(5, queue.peek().size)
    }

    @Test
    fun `ack removes exactly the acknowledged messages`() {
        val storage = MemoryStorage()
        val queue = storage.queue()
        val first = queue.append("779776919", "100", 1_000L)
        val second = queue.append("779776919", "100", 1_000L)
        queue.append("779776920", "300", 3_000L)

        queue.ack(setOf(first.id, second.id))

        assertEquals(listOf("779776920"), queue.peek().map { it.sender })
    }

    @Test
    fun `ack ignores unknown ids and an empty ack set`() {
        val storage = MemoryStorage()
        val queue = storage.queue()
        queue.append("779776919", "100", 1_000L)

        queue.ack(emptySet())
        queue.ack(setOf("not-a-real-id"))

        assertEquals(1, queue.peek().size)
    }

    @Test
    fun `pending messages survive a restart of the app`() {
        val storage = MemoryStorage()
        storage.queue().append("779776919", "100", 1_000L)

        // عملية جديدة: صنف جديد يقرأ نفس التخزين.
        val afterRestart = storage.queue()
        assertEquals(listOf("100"), afterRestart.peek().map { it.body })
    }

    @Test
    fun `the oldest messages are dropped once the cap is exceeded`() {
        val storage = MemoryStorage()
        val queue = storage.queue()
        val extra = 5
        repeat(SmsInboxQueue.MAX_ITEMS + extra) { index ->
            queue.append("sender", "body$index", index.toLong())
        }

        val pending = queue.peek(limit = Int.MAX_VALUE)
        assertEquals(SmsInboxQueue.MAX_ITEMS, pending.size)
        // أقدم `extra` رسالة أُسقطت، والترتيب محفوظ.
        assertEquals("body$extra", pending.first().body)
        assertEquals("body${SmsInboxQueue.MAX_ITEMS + extra - 1}", pending.last().body)
    }

    @Test
    fun `a corrupt payload never blocks the messages that follow it`() {
        val storage = MemoryStorage()
        storage.raw = "{ this is not a json array"

        val queue = storage.queue()
        assertTrue(queue.peek().isEmpty())

        queue.append("779776919", "100", 1_000L)
        assertEquals(listOf("100"), queue.peek().map { it.body })
    }

    @Test
    fun `a partially written payload is skipped as a whole instead of crashing`() {
        val storage = MemoryStorage()
        // عنصر سليم وعنصر ناقص الحقول: القراءة يجب ألا ترمي استثناءً.
        storage.raw = """[{"id":"a","sender":"s","body":"b","timestampMillis":1},{"id":"b"}]"""

        val queue = storage.queue()
        assertTrue(queue.peek().isEmpty())
        queue.append("779776919", "100", 2_000L)
        assertEquals(listOf("100"), queue.peek().map { it.body })
    }
}
