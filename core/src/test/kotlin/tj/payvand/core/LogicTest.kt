package tj.payvand.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Модульные тесты без сервера: выполняются при любой сборке. */
class LogicTest {
    private fun msg(at: String) = Message("m", "c", "me", createdAt = at)
    private fun member(id: String, read: String?, delivered: String?) = Member("c", id, "member", read, delivered)

    @Test fun parsesPostgresTimestamps() {
        assertEquals(Instant.parse("2026-11-13T10:17:16.647681Z"), Time.parse("2026-11-13T10:17:16.647681+00:00"))
        assertEquals(Instant.parse("2026-11-13T05:17:16Z"), Time.parse("2026-11-13 10:17:16+05:00"))
        assertNotNull(Time.parse("2026-11-13T10:17:16.6Z"))
        assertNull(Time.parse("")); assertNull(Time.parse(null)); assertNull(Time.parse("вчера"))
    }

    @Test fun onlineWithinTwoMinutes() {
        val now = Instant.parse("2026-11-13T10:00:00Z")
        assertTrue(Time.isOnline("2026-11-13T09:59:00+00:00", now))
        assertFalse(Time.isOnline("2026-11-13T09:57:00+00:00", now))
        assertFalse(Time.isOnline(null, now))
    }

    @Test fun deliveryStatusFromReceipts() {
        val m = msg("2026-11-13T10:00:00+00:00")
        val before = "2026-11-13T09:00:00+00:00"; val after = "2026-11-13T10:00:01+00:00"
        assertEquals(DeliveryStatus.SENT, Receipts.statusOf(m, "me", listOf(member("me", after, after), member("bob", before, before))))
        assertEquals(DeliveryStatus.DELIVERED, Receipts.statusOf(m, "me", listOf(member("bob", before, after))))
        assertEquals(DeliveryStatus.READ, Receipts.statusOf(m, "me", listOf(member("bob", after, after))))
        // в группе достаточно одного прочитавшего
        assertEquals(DeliveryStatus.READ, Receipts.statusOf(m, "me", listOf(member("bob", before, before), member("eve", after, after))))
        assertEquals(DeliveryStatus.SENT, Receipts.statusOf(m, "me", emptyList()))
    }

    @Test fun conversationRules() {
        val channel = ConversationSummary("1", "channel", "News", myRole = "member")
        assertFalse(channel.canPost); assertTrue(channel.copy(myRole = "admin").canPost)
        val direct = ConversationSummary("2", "direct", peerName = "", peerUsername = "saidali")
        assertEquals("saidali", direct.displayTitle); assertTrue(direct.canPost); assertFalse(direct.copy(blocked = true).canPost)
        assertTrue(Limits.USERNAME_REGEX.matches("alisher_tj")); assertFalse(Limits.USERNAME_REGEX.matches("1abc")); assertFalse(Limits.USERNAME_REGEX.matches("Али"))
        assertTrue(Profile("x", username = "a_b1", displayName = "А").isComplete); assertFalse(Profile("x").isComplete)
    }
}
