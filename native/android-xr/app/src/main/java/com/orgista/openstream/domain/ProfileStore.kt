package com.orgista.openstream.domain

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists the content policy in app-private storage with an irreversible
 * kids lock: once the lock exists, every failure mode (missing, edited, or
 * unparseable profile) resolves to a kids policy — tampering can only make
 * the filter stricter. Removing the lock requires clearing the app's data,
 * which is exactly the documented uninstall-and-set-up-again reset.
 */
class ProfileStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("openstream.profile", Context.MODE_PRIVATE)

    fun loadActivePolicy(): ContentPolicy? {
        val lock = prefs.getString(KEY_KIDS_LOCK, null)
        val raw = prefs.getString(KEY_PROFILE, null)
        val parsed = raw?.let(::parseProfile)

        if (lock != null) {
            return if (parsed is ContentPolicy.Kids && checksum(raw) == lock) parsed else strictestKidsPolicy
        }
        if (parsed is ContentPolicy.Kids) {
            // A kids profile must always carry its lock; restore the seal.
            prefs.edit().putString(KEY_KIDS_LOCK, checksum(raw ?: "")).apply()
            return parsed
        }
        return parsed
    }

    fun completeStandardOnboarding(): ContentPolicy {
        val raw = JSONObject().put("mode", "standard").toString()
        prefs.edit().putString(KEY_PROFILE, raw).apply()
        return ContentPolicy.Standard
    }

    fun enableKidsMode(policy: ContentPolicy.Kids): ContentPolicy {
        val raw = JSONObject()
            .put("mode", "kids")
            .put("cap", policy.cap.name)
            .put("blockedTerms", JSONArray(policy.blockedTerms))
            .put("createdAt", policy.createdAt)
            .apply {
                policy.adminPinHash?.let { put("adminPinHash", it) }
                policy.adminPinSalt?.let { put("adminPinSalt", it) }
            }
            .toString()
        prefs.edit()
            .putString(KEY_PROFILE, raw)
            .putString(KEY_KIDS_LOCK, checksum(raw))
            .apply()
        return policy
    }

    /**
     * First-use PIN claim for kids installs created before the admin PIN
     * existed: stores the PIN inside the sealed profile and re-seals the lock.
     * Never replaces a PIN that is already configured.
     */
    fun setAdminPin(pin: String): ContentPolicy? {
        val current = loadActivePolicy()
        if (current !is ContentPolicy.Kids || AdminPinPolicy.isConfigured(current)) return current
        require(AdminPinPolicy.isValidPin(pin)) { "Enter a ${AdminPinPolicy.MIN_LENGTH}-${AdminPinPolicy.MAX_LENGTH} digit PIN." }
        val salt = AdminPinPolicy.newSalt()
        return enableKidsMode(
            current.copy(adminPinHash = AdminPinPolicy.hash(pin, salt), adminPinSalt = salt),
        )
    }

    private fun parseProfile(raw: String): ContentPolicy? = try {
        val json = JSONObject(raw)
        when (json.optString("mode")) {
            "standard" -> ContentPolicy.Standard
            "kids" -> {
                val cap = KidsCap.entries.firstOrNull { it.name == json.optString("cap") }
                    ?: KidsCap.LITTLE_KIDS
                val terms = json.optJSONArray("blockedTerms") ?: JSONArray()
                ContentPolicy.Kids(
                    cap = cap,
                    blockedTerms = (0 until terms.length()).map { terms.getString(it) },
                    createdAt = json.optString("createdAt", "unknown"),
                    adminPinHash = json.optString("adminPinHash").takeIf { it.isNotBlank() },
                    adminPinSalt = json.optString("adminPinSalt").takeIf { it.isNotBlank() },
                )
            }
            else -> null
        }
    } catch (_: Exception) {
        null
    }

    companion object {
        private const val KEY_PROFILE = "profile.v1"
        private const val KEY_KIDS_LOCK = "kidsLock.v1"
        private const val LOCK_SALT = "openstream-kids-lock"

        /**
         * FNV-1a seal pairing the lock with the exact stored profile bytes.
         * Tamper evidence for casual edits, not a cryptographic boundary; the
         * enforcement rule is that a present lock always resolves to kids.
         */
        fun checksum(value: String): String {
            var hash = 0x811c9dc5.toInt()
            for (character in "$LOCK_SALT:$value") {
                hash = hash xor character.code
                hash *= 0x01000193
            }
            return Integer.toUnsignedString(hash, 16).padStart(8, '0')
        }
    }
}
