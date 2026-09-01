package com.orgista.openstream.ui

import com.orgista.openstream.domain.KidsCap

object KidsAudiencePolicy {
    fun capForAge(age: Int): KidsCap = when {
        age <= 6 -> KidsCap.LITTLE_KIDS
        age <= 9 -> KidsCap.BIG_KIDS
        else -> KidsCap.TEENS
    }

    fun ageRange(cap: KidsCap): String = when (cap) {
        KidsCap.LITTLE_KIDS -> "Ages 6 and under"
        KidsCap.BIG_KIDS -> "Ages 7–9"
        KidsCap.TEENS -> "Ages 10–14"
    }
}

object OnboardingCopy {
    const val MODE_TITLE = "Who’s watching?"
    const val AGE_TITLE = "Age range"
    const val BLOCK_TITLE = "Extra blocks"
    const val PIN_TITLE = "Admin PIN"
    const val CONFIRM_TITLE = "Confirm Kids Mode"
    const val KIDS_WARNING = "Cannot be turned off"
    const val PERMANENCE =
        "Kids Mode cannot be turned off. The PIN only opens Settings and Sources. Remove the app to start over."
    const val ACKNOWLEDGEMENT = "I understand"

    fun blockAction(blockedCount: Int): String = if (blockedCount == 0) "Skip" else "Continue"
}

data class EmptyDiscoverCopy(
    val title: String,
    val body: String,
    val action: String,
)

enum class DiscoverEmptyReason {
    OFFLINE_NO_DOWNLOADS,
    NO_SOURCES,
    SOURCES_EMPTY,
    KIDS_FILTERED,
}

object DiscoverEmptyStatePolicy {
    fun copy(reason: DiscoverEmptyReason, ageRange: String? = null): EmptyDiscoverCopy = when (reason) {
        DiscoverEmptyReason.OFFLINE_NO_DOWNLOADS -> EmptyDiscoverCopy(
            title = "No downloads",
            body = "Connect to Wi-Fi to browse. Save titles before your next offline trip.",
            action = "Wi-Fi settings",
        )
        DiscoverEmptyReason.NO_SOURCES -> EmptyDiscoverCopy(
            title = "Nothing here yet",
            body = "Connect a library, add-on, or YouTube channel.",
            action = "Open Sources",
        )
        DiscoverEmptyReason.SOURCES_EMPTY -> EmptyDiscoverCopy(
            title = "No titles available",
            body = "Connected sources returned no titles. Check their status in Sources.",
            action = "Review Sources",
        )
        DiscoverEmptyReason.KIDS_FILTERED -> EmptyDiscoverCopy(
            title = "No titles for ${ageRange ?: "this age range"}",
            body = "Connected sources have no titles rated for this age range. A guardian can review Sources.",
            action = "Review Sources",
        )
    }
}
