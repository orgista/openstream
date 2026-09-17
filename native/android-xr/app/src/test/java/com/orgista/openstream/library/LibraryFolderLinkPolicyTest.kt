package com.orgista.openstream.library

import com.orgista.openstream.data.NasConnection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryFolderLinkPolicyTest {
    private fun connection(id: String, name: String) =
        NasConnection(id = id, name = name, host = "192.168.1.87", share = "media", username = "u", password = "p")

    private fun folder(connectionId: String, connectionName: String) = LibraryFolder(
        id = "folder-1",
        connectionId = connectionId,
        connectionName = connectionName,
        path = "movies",
        kind = LibraryKind.MOVIES,
    )

    @Test
    fun `a folder whose connection exists is left untouched`() {
        val connections = listOf(connection("abc", "ExampleNAS"))
        val result = LibraryFolderLinkPolicy.resolve(listOf(folder("abc", "ExampleNAS")), connections)
        assertFalse(result.changed)
        assertTrue(result.orphaned.isEmpty())
        assertEquals("abc", result.folders.single().connectionId)
    }

    @Test
    fun `a stale connection id relinks to the uniquely matching share name`() {
        val connections = listOf(connection("new-id", "ExampleNAS"))
        val result = LibraryFolderLinkPolicy.resolve(listOf(folder("stale-id", "ExampleNAS ")), connections)
        assertTrue(result.changed)
        assertTrue(result.orphaned.isEmpty())
        assertEquals("new-id", result.folders.single().connectionId)
        // The canonical share name from the connection replaces the stored one.
        assertEquals("ExampleNAS", result.folders.single().connectionName)
    }

    @Test
    fun `with no connections at all the folder is reported orphaned`() {
        val result = LibraryFolderLinkPolicy.resolve(listOf(folder("stale-id", "ExampleNAS")), emptyList())
        assertFalse(result.changed)
        assertEquals(1, result.orphaned.size)
        // Left in place so the viewer can reconnect the share instead of losing the folder.
        assertEquals("stale-id", result.folders.single().connectionId)
    }

    @Test
    fun `an ambiguous share name is never guessed`() {
        val connections = listOf(connection("id-1", "ExampleNAS"), connection("id-2", "ExampleNAS"))
        val result = LibraryFolderLinkPolicy.resolve(listOf(folder("stale-id", "ExampleNAS")), connections)
        assertFalse(result.changed)
        assertEquals(1, result.orphaned.size)
    }

    @Test
    fun `a different share name stays orphaned`() {
        val connections = listOf(connection("id-1", "Backup"))
        val result = LibraryFolderLinkPolicy.resolve(listOf(folder("stale-id", "ExampleNAS")), connections)
        assertEquals(1, result.orphaned.size)
        assertTrue(LibraryFolderLinkPolicy.isOrphaned(folder("stale-id", "ExampleNAS"), connections))
    }

    @Test
    fun `mixed folders resolve independently`() {
        val connections = listOf(connection("live", "ExampleNAS"))
        val folders = listOf(
            folder("live", "ExampleNAS"),
            folder("stale", "ExampleNAS").copy(id = "folder-2"),
            folder("gone", "OldNas").copy(id = "folder-3"),
        )
        val result = LibraryFolderLinkPolicy.resolve(folders, connections)
        assertEquals(1, result.relinked.size)
        assertEquals(1, result.orphaned.size)
        assertEquals("folder-3", result.orphaned.single().id)
        assertEquals(3, result.folders.size)
    }
}
