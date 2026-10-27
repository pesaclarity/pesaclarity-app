package com.pesaclarity.app

import android.app.Notification
import android.app.Person
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads money messages from other apps' notifications, such as the messages
 * app showing an M-Pesa SMS. Only notifications whose sender is one the
 * person chose (see [NotificationCaptureStore.watched]) are kept; the rest
 * are never read past the sender. Kept messages wait, encrypted, until the
 * app drains them.
 */
class NotificationCaptureService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        val notification = sbn.notification ?: return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val watched = NotificationCaptureStore.watched(this)
        if (watched.isEmpty()) return
        val found =
            messagesIn(notification.extras ?: return, sbn.postTime)
                .filter { SmsChannel.normalise(it.sender) in watched }
        if (found.isEmpty()) return
        if (NotificationCaptureStore.append(this, found)) {
            NotificationCaptureStore.announceArrival()
        }
    }

    internal data class Message(val sender: String, val body: String, val receivedAtMillis: Long)

    private fun messagesIn(extras: Bundle, postedAt: Long): List<Message> {
        val title =
            (extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
                ?: extras.getCharSequence(Notification.EXTRA_TITLE))
                ?.toString()
                .orEmpty()
        // Messaging-style notifications carry each message with its own sender and time.
        @Suppress("DEPRECATION")
        val bundles = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        if (!bundles.isNullOrEmpty()) {
            return bundles.mapNotNull { messageFrom(it, title, postedAt) }
        }
        val body =
            (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT))
                ?.toString()
        if (title.isBlank() || body.isNullOrBlank()) return emptyList()
        return listOf(Message(title, body, postedAt))
    }

    private fun messageFrom(parcel: Parcelable, title: String, postedAt: Long): Message? {
        val bundle = parcel as? Bundle ?: return null
        val body = bundle.getCharSequence("text")?.toString()
        if (body.isNullOrBlank()) return null
        val sender = senderOf(bundle) ?: title
        if (sender.isBlank()) return null
        return Message(sender, body, bundle.getLong("time").takeIf { it > 0 } ?: postedAt)
    }

    private fun senderOf(bundle: Bundle): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            val person = bundle.getParcelable<Person>("sender_person")
            person?.name?.toString()?.takeIf { it.isNotBlank() }?.let { return it }
        }
        return bundle.getCharSequence("sender")?.toString()?.takeIf { it.isNotBlank() }
    }
}
