package com.orgista.openstream.library

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

enum class LibraryKind { MOVIES, TV, AUTO }

/**
 * A folder the user added as a library: a NAS connection plus a sub-path,
 * indexed into organized Movies/TV. Credentials live with the connection, not
 * here.
 */
data class LibraryFolder(
    val id: String,
    val connectionId: String,
    val connectionName: String,
    val path: String,
    val kind: LibraryKind,
)

class LibraryStore(context: Context) {
    private val prefs = context.getSharedPreferences("openstream.library", Context.MODE_PRIVATE)

    var tmdbApiKey: String
        get() = prefs.getString(KEY_TMDB, "") ?: ""
        set(value) { prefs.edit().putString(KEY_TMDB, value.trim()).apply() }

    var omdbApiKey: String
        get() = prefs.getString(KEY_OMDB, "") ?: ""
        set(value) { prefs.edit().putString(KEY_OMDB, value.trim()).apply() }

    /** Metadata keys are never used until the viewer explicitly opts in. */
    var metadataOptIn: Boolean
        get() = prefs.getBoolean(KEY_METADATA_OPT_IN, false)
        set(value) { prefs.edit().putBoolean(KEY_METADATA_OPT_IN, value).apply() }

    fun reusableTmdbCredential(): String =
        MetadataCredentialPolicy.reusableCredential(metadataOptIn, tmdbApiKey)

    fun reusableOmdbCredential(): String =
        MetadataCredentialPolicy.reusableCredential(metadataOptIn, omdbApiKey)

    /** When on, the player selects a subtitle track automatically on start. */
    var autoSubtitles: Boolean
        get() = prefs.getBoolean(KEY_AUTO_SUBS, false)
        set(value) { prefs.edit().putBoolean(KEY_AUTO_SUBS, value).apply() }

    /** When enabled, a completed device-backed playback removes only its own offline copy. */
    var deleteOfflineAfterWatched: Boolean
        get() = prefs.getBoolean(KEY_DELETE_OFFLINE_AFTER_WATCHED, false)
        set(value) { prefs.edit().putBoolean(KEY_DELETE_OFFLINE_AFTER_WATCHED, value).apply() }

    fun folders(): List<LibraryFolder> {
        val raw = prefs.getString(KEY_FOLDERS, "[]") ?: "[]"
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { index ->
                val json = array.getJSONObject(index)
                LibraryFolder(
                    id = json.getString("id"),
                    connectionId = json.getString("connectionId"),
                    connectionName = json.optString("connectionName"),
                    path = json.optString("path"),
                    kind = runCatching { LibraryKind.valueOf(json.optString("kind")) }.getOrDefault(LibraryKind.AUTO),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun addFolder(connectionId: String, connectionName: String, path: String, kind: LibraryKind): LibraryFolder {
        val folder = LibraryFolder(UUID.randomUUID().toString(), connectionId, connectionName, path, kind)
        writeFolders(folders() + folder)
        return folder
    }

    fun removeFolder(id: String) = writeFolders(folders().filter { it.id != id })

    /** Persists folders after [LibraryFolderLinkPolicy] repairs their connection ids. */
    fun replaceFolders(list: List<LibraryFolder>) = writeFolders(list)

    private fun writeFolders(list: List<LibraryFolder>) {
        val array = JSONArray()
        list.forEach { folder ->
            array.put(
                JSONObject()
                    .put("id", folder.id)
                    .put("connectionId", folder.connectionId)
                    .put("connectionName", folder.connectionName)
                    .put("path", folder.path)
                    .put("kind", folder.kind.name),
            )
        }
        prefs.edit().putString(KEY_FOLDERS, array.toString()).apply()
    }

    companion object {
        private const val KEY_FOLDERS = "folders.v1"
        private const val KEY_TMDB = "tmdbApiKey.v1"
        private const val KEY_OMDB = "omdbApiKey.v1"
        private const val KEY_METADATA_OPT_IN = "metadataOptIn.v1"
        private const val KEY_AUTO_SUBS = "autoSubtitles.v1"
        private const val KEY_DELETE_OFFLINE_AFTER_WATCHED = "deleteOfflineAfterWatched.v1"
    }
}
