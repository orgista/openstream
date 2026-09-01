package com.cyberbanksy.openstream.xr

import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import androidx.xr.runtime.Session
import androidx.xr.runtime.SessionCreateSuccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private lateinit var status: TextView
    private var session: Session? = null
    private var videoAdapter: SceneCoreVideoAdapter? = null
    private var pendingMedia: ImmersiveMedia? = null

    private val openVideo = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let {
            runCatching {
                contentResolver.takePersistableUriPermission(
                    it,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            play(classify(it))
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(createContentView())

        intent?.data?.let { uri -> pendingMedia = processIncomingUri(uri) }
        lifecycleScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    Session.create(
                        context = this@MainActivity,
                        lifecycleOwner = this@MainActivity,
                    )
                }
            }.onSuccess { result ->
                if (result is SessionCreateSuccess) {
                    val created = result.session
                    session = created
                    videoAdapter = SceneCoreVideoAdapter(this@MainActivity, created, ::showStatus)
                    pendingMedia?.let(::play)
                    pendingMedia = null
                    if (intent?.data == null) showStatus("Choose a video to begin in full space")
                } else {
                    showStatus("Android XR SceneCore is not available on this device.")
                }
            }.onFailure {
                showStatus("Android XR SceneCore is not available on this device.")
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.data?.let { uri ->
            processIncomingUri(uri)?.let(::play)
        }
    }

    override fun onStop() {
        videoAdapter?.pause()
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        videoAdapter?.resume()
    }

    override fun onDestroy() {
        videoAdapter?.close()
        videoAdapter = null
        session = null
        super.onDestroy()
    }

    fun processIncomingUri(uri: Uri?): ImmersiveMedia? {
        if (uri == null) return null
        val scheme = uri.scheme?.lowercase()
        if (!isAllowedScheme(scheme)) {
            showStatus("Unsupported media URI scheme: ${uri.scheme}")
            return null
        }
        if (scheme == "content") {
            runCatching {
                contentResolver.takePersistableUriPermission(
                    uri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        }
        return runCatching { classify(uri) }.getOrElse {
            showStatus("Invalid media intent parameters.")
            null
        }
    }

    private fun classify(uri: Uri): ImmersiveMedia = ImmersiveMediaClassifier.classify(
        uri = uri,
        title = uri.lastPathSegment,
        projectionMetadata = intent.getStringExtra("projection"),
        stereoMetadata = intent.getStringExtra("stereo"),
        dynamicRangeMetadata = intent.getStringExtra("dynamicRange"),
    )

    private fun play(media: ImmersiveMedia) {
        val adapter = videoAdapter
        if (adapter == null) {
            pendingMedia = media
            showStatus("Starting Android XR…")
        } else {
            runCatching {
                adapter.play(media)
            }.onFailure { error ->
                showStatus("Playback failed: ${error.message ?: "Unable to initialize video playback."}")
            }
        }
    }

    private fun showStatus(message: String) {
        runOnUiThread { status.text = message }
    }

    private fun createContentView(): LinearLayout {
        status = TextView(this).apply {
            setText(R.string.starting_xr)
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val choose = Button(this).apply {
            setText(R.string.choose_video)
            setOnClickListener { openVideo.launch(arrayOf("video/*")) }
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(Color.rgb(5, 6, 8))
            addView(
                status,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f),
            )
            addView(
                choose,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT),
            )
        }
    }

    companion object {
        val ALLOWED_SCHEMES = setOf("content", "file", "http", "https")
        fun isAllowedScheme(scheme: String?): Boolean = scheme?.lowercase() in ALLOWED_SCHEMES
    }
}
