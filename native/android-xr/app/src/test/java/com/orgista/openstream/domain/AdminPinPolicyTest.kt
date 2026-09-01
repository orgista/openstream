package com.orgista.openstream.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdminPinPolicyTest {
    @Test
    fun `pin validity requires four to eight digits`() {
        assertFalse(AdminPinPolicy.isValidPin("123"))
        assertTrue(AdminPinPolicy.isValidPin("1234"))
        assertTrue(AdminPinPolicy.isValidPin("12345678"))
        assertFalse(AdminPinPolicy.isValidPin("123456789"))
        assertFalse(AdminPinPolicy.isValidPin("12a4"))
        assertFalse(AdminPinPolicy.isValidPin(""))
    }

    @Test
    fun `a created kids policy verifies its own pin and rejects others`() {
        val policy = createKidsPolicy(KidsCap.BIG_KIDS, emptyList(), adminPin = "4271")
        assertTrue(AdminPinPolicy.isConfigured(policy))
        assertTrue(AdminPinPolicy.verify(policy, "4271"))
        assertFalse(AdminPinPolicy.verify(policy, "4272"))
        assertFalse(AdminPinPolicy.verify(policy, ""))
    }

    @Test
    fun `legacy kids policies without a pin are unconfigured and never verify`() {
        val legacy = createKidsPolicy(KidsCap.TEENS, emptyList())
        assertFalse(AdminPinPolicy.isConfigured(legacy))
        assertFalse(AdminPinPolicy.verify(legacy, "0000"))
        // The fail-closed policy carries no PIN, so tampering never grants admin access.
        assertFalse(AdminPinPolicy.verify(strictestKidsPolicy, "0000"))
    }

    @Test
    fun `standard profiles need no pin`() {
        assertFalse(AdminPinPolicy.isConfigured(ContentPolicy.Standard))
        assertTrue(AdminPinPolicy.verify(ContentPolicy.Standard, "anything"))
    }

    @Test
    fun `hashing is salted and deterministic`() {
        val salt = AdminPinPolicy.newSalt()
        assertEquals(AdminPinPolicy.hash("1234", salt), AdminPinPolicy.hash("1234", salt))
        val otherSalt = AdminPinPolicy.newSalt()
        assertFalse(AdminPinPolicy.hash("1234", salt) == AdminPinPolicy.hash("1234", otherSalt))
    }
}
