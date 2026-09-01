package com.orgista.openstream.library

import com.orgista.openstream.data.NasConnection

data class LibraryLinkResult(
    /** Folders with connection ids repaired where a unique match existed. */
    val folders: List<LibraryFolder>,
    /** Folders repaired in this pass; non-zero means the caller should persist. */
    val relinked: List<LibraryFolder>,
    /** Folders whose NAS share is still not configured on this device. */
    val orphaned: List<LibraryFolder>,
) {
    val changed: Boolean get() = relinked.isNotEmpty()
}

/**
 * Keeps added library folders attached to their NAS share.
 *
 * A folder stores the connection's id, so removing and re-adding the same
 * share leaves the folder pointing at an id that no longer exists. The indexer
 * then has nothing to scan and the library reads as empty with no explanation.
 * Re-linking by unique share name repairs that case, and whatever remains
 * unmatched is reported so the UI can ask for the share instead of silently
 * indexing nothing.
 */
object LibraryFolderLinkPolicy {
    fun resolve(folders: List<LibraryFolder>, connections: List<NasConnection>): LibraryLinkResult {
        val byId = connections.associateBy { it.id }
        val byName = connections.groupBy { normalize(it.name) }
        val resolved = ArrayList<LibraryFolder>(folders.size)
        val relinked = ArrayList<LibraryFolder>()
        val orphaned = ArrayList<LibraryFolder>()

        for (folder in folders) {
            if (byId.containsKey(folder.connectionId)) {
                resolved += folder
                continue
            }
            // Only a single same-name share is an unambiguous repair; anything
            // else stays orphaned so the viewer decides which share to use.
            val match = byName[normalize(folder.connectionName)]?.singleOrNull()
            if (match != null) {
                val repaired = folder.copy(connectionId = match.id, connectionName = match.name)
                resolved += repaired
                relinked += repaired
            } else {
                resolved += folder
                orphaned += folder
            }
        }
        return LibraryLinkResult(folders = resolved, relinked = relinked, orphaned = orphaned)
    }

    fun isOrphaned(folder: LibraryFolder, connections: List<NasConnection>): Boolean =
        resolve(listOf(folder), connections).orphaned.isNotEmpty()

    private fun normalize(value: String): String = value.trim().lowercase()
}
