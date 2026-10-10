package com.orgista.openstream.ui

/** A local video/audio file to play: opened with OpenStream, picked, or dropped. */
data class LocalMedia(val uri: String, val title: String)

/**
 * Local files on desktop (T-File_Handlers, T-File_Picker, T-Drag_Drop_Support).
 * They play straight through the player: Media3's DefaultDataSource reads
 * content:// and file:// URIs, so no source needs to be set up.
 */
object LocalMediaPolicy {
    const val SUBTITLE = "Local file"

    fun accepts(scheme: String?, mimeType: String?): Boolean {
        if (scheme != "content" && scheme != "file") return false
        // Some file managers send no type; the player reports unplayable files.
        if (mimeType.isNullOrBlank()) return true
        return mimeType.startsWith("video/") || mimeType.startsWith("audio/")
    }

    fun request(media: LocalMedia): PlaybackRequest = PlaybackRequest(
        title = media.title,
        subtitle = SUBTITLE,
        uri = media.uri,
        mediaId = "local:${media.uri}",
    )
}
