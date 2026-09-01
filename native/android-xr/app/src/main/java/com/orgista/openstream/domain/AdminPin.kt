package com.orgista.openstream.domain

import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Guardian PIN for the admin surfaces (Settings and source management) on a
 * kids-locked install. The PIN gates configuration only — it never unlocks or
 * removes the kids content filter. It is stored as a salted SHA-256 inside the
 * sealed kids profile, so editing the stored PIN by hand invalidates the
 * profile seal and the install fails closed to the strictest cap, which has
 * no PIN and therefore no admin access.
 */
object AdminPinPolicy {
    const val MIN_LENGTH = 4
    const val MAX_LENGTH = 8

    fun isValidPin(pin: String): Boolean =
        pin.length in MIN_LENGTH..MAX_LENGTH && pin.all(Char::isDigit)

    fun newSalt(): String {
        val bytes = ByteArray(16)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    fun hash(pin: String, salt: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest("$salt:$pin".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /** A standard profile needs no PIN; a kids profile does once one is stored. */
    fun isConfigured(policy: ContentPolicy): Boolean =
        policy is ContentPolicy.Kids &&
            !policy.adminPinHash.isNullOrBlank() &&
            !policy.adminPinSalt.isNullOrBlank()

    fun verify(policy: ContentPolicy, pin: String): Boolean {
        if (policy !is ContentPolicy.Kids) return true
        val storedHash = policy.adminPinHash ?: return false
        val storedSalt = policy.adminPinSalt ?: return false
        return MessageDigest.isEqual(
            storedHash.toByteArray(Charsets.UTF_8),
            hash(pin, storedSalt).toByteArray(Charsets.UTF_8),
        )
    }
}
