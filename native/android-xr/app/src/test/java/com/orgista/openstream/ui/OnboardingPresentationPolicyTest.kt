package com.orgista.openstream.ui

import com.orgista.openstream.domain.KidsCap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingPresentationPolicyTest {
    @Test
    fun `age seven selects the big kids certification range`() {
        assertEquals(KidsCap.BIG_KIDS, KidsAudiencePolicy.capForAge(7))
        assertEquals("Ages 7–9", KidsAudiencePolicy.ageRange(KidsCap.BIG_KIDS))
    }

    @Test
    fun `setup copy stays terse without weakening the kids permanence warning`() {
        assertEquals("Who’s watching?", OnboardingCopy.MODE_TITLE)
        assertEquals("Age range", OnboardingCopy.AGE_TITLE)
        assertEquals("Extra blocks", OnboardingCopy.BLOCK_TITLE)
        assertEquals("Admin PIN", OnboardingCopy.PIN_TITLE)
        assertEquals("Skip", OnboardingCopy.blockAction(0))
        assertEquals("Continue", OnboardingCopy.blockAction(1))
        assertTrue(OnboardingCopy.PERMANENCE.contains("cannot be turned off"))
        assertTrue(OnboardingCopy.PERMANENCE.split(Regex("\\s+")).size <= 20)
    }

    @Test
    fun `offline discover offers a direct recovery action`() {
        assertEquals(
            EmptyDiscoverCopy(
                title = "No downloads",
                body = "Connect to Wi-Fi to browse. Save titles before your next offline trip.",
                action = "Wi-Fi settings",
            ),
            DiscoverEmptyStatePolicy.copy(DiscoverEmptyReason.OFFLINE_NO_DOWNLOADS),
        )
    }

    @Test
    fun `online discover points to source setup`() {
        assertEquals(
            EmptyDiscoverCopy(
                title = "Nothing here yet",
                body = "Connect a library, add-on, or YouTube channel.",
                action = "Open Sources",
            ),
            DiscoverEmptyStatePolicy.copy(DiscoverEmptyReason.NO_SOURCES),
        )
    }

    @Test
    fun `kids discover explains when connected titles are filtered`() {
        assertEquals(
            EmptyDiscoverCopy(
                title = "No titles for Ages 7–9",
                body = "Connected sources have no titles rated for this age range. A guardian can review Sources.",
                action = "Review Sources",
            ),
            DiscoverEmptyStatePolicy.copy(
                reason = DiscoverEmptyReason.KIDS_FILTERED,
                ageRange = "Ages 7–9",
            ),
        )
    }

    @Test
    fun `configured source failure does not look like missing setup`() {
        assertEquals(
            EmptyDiscoverCopy(
                title = "No titles available",
                body = "Connected sources returned no titles. Check their status in Sources.",
                action = "Review Sources",
            ),
            DiscoverEmptyStatePolicy.copy(DiscoverEmptyReason.SOURCES_EMPTY),
        )
    }
}
