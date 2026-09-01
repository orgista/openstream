package com.orgista.openstream.domain

import com.orgista.openstream.data.MediaItem

/** The active content policy: full library, or a locked kids configuration. */
sealed interface ContentPolicy {
    data object Standard : ContentPolicy

    data class Kids(
        val cap: KidsCap,
        val blockedTerms: List<String>,
        val createdAt: String,
        val adminPinHash: String? = null,
        val adminPinSalt: String? = null,
    ) : ContentPolicy
}

/** Fail-closed policy used whenever a kids-locked profile cannot be trusted. */
val strictestKidsPolicy = ContentPolicy.Kids(KidsCap.LITTLE_KIDS, emptyList(), "unknown")

fun createKidsPolicy(cap: KidsCap, blockedTerms: List<String>, adminPin: String? = null): ContentPolicy.Kids {
    val salt = adminPin?.let { AdminPinPolicy.newSalt() }
    return ContentPolicy.Kids(
        cap = cap,
        blockedTerms = blockedTerms.map { it.trim().lowercase() }.filter { it.isNotEmpty() }.distinct().take(100),
        createdAt = java.time.Instant.now().toString(),
        adminPinHash = adminPin?.let { pin -> AdminPinPolicy.hash(pin, requireNotNull(salt)) },
        adminPinSalt = salt,
    )
}

/**
 * Whether an item may be shown or played. Unrated and unrecognized
 * certifications are blocked in Kids Mode; guardian terms match against the
 * title, subtitle, and synopsis.
 */
fun isItemAllowed(item: MediaItem, policy: ContentPolicy): Boolean {
    if (policy !is ContentPolicy.Kids) return true
    if (!isRatingAllowed(item.rating, policy.cap.maxAge)) return false
    if (policy.blockedTerms.isEmpty()) return true
    val haystack = "${item.title} ${item.subtitle.orEmpty()} ${item.synopsis}".lowercase()
    return policy.blockedTerms.none { haystack.contains(it) }
}

fun filterCatalog(items: List<MediaItem>, policy: ContentPolicy): List<MediaItem> =
    if (policy is ContentPolicy.Kids) items.filter { isItemAllowed(it, policy) } else items
