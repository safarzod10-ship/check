package tj.payvand.core

import java.time.Instant
import java.time.OffsetDateTime

object Time {
    /** Разбирает timestamptz из Postgres/Realtime; null — если строка пуста или некорректна. */
    fun parse(s: String?): Instant? {
        if (s.isNullOrBlank()) return null
        return runCatching { OffsetDateTime.parse(s.replace(' ', 'T')).toInstant() }
            .recoverCatching { Instant.parse(s) }
            .getOrNull()
    }

    fun isOnline(lastSeen: String?, now: Instant = Instant.now()): Boolean {
        val t = parse(lastSeen) ?: return false
        return now.epochSecond - t.epochSecond < 120
    }
}

enum class DeliveryStatus { SENDING, FAILED, SENT, DELIVERED, READ }

object Receipts {
    /**
     * Статус моего сообщения по отметкам остальных участников:
     * READ — кто-то прочитал, DELIVERED — чьё-то устройство получило, иначе SENT (сохранено сервером).
     */
    fun statusOf(message: Message, myId: String, members: List<Member>): DeliveryStatus {
        val created = Time.parse(message.createdAt) ?: return DeliveryStatus.SENT
        val others = members.filter { it.userId != myId }
        if (others.any { m -> Time.parse(m.lastReadAt)?.let { !it.isBefore(created) } == true }) return DeliveryStatus.READ
        if (others.any { m -> Time.parse(m.lastDeliveredAt)?.let { !it.isBefore(created) } == true }) return DeliveryStatus.DELIVERED
        return DeliveryStatus.SENT
    }
}
