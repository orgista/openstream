package com.orgista.openstream

import android.app.Activity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.DragAndDropPermissions
import android.view.DragEvent
import android.util.Rational
import android.view.KeyEvent
import android.view.KeyboardShortcutGroup
import android.view.KeyboardShortcutInfo
import android.view.Menu
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.core.view.WindowCompat
import com.orgista.openstream.ui.LocalMedia
import com.orgista.openstream.ui.LocalMediaDropZone
import com.orgista.openstream.ui.LocalMediaPolicy
import com.orgista.openstream.ui.OpenStreamApp
import com.orgista.openstream.ui.OpenStreamLaunchGate
import com.orgista.openstream.ui.OpenStreamTheme
import com.orgista.openstream.ui.PlaybackWindowHost
import com.orgista.openstream.device.DevicePresentationPolicy
import com.orgista.openstream.device.OrientationPreference
import com.orgista.openstream.xr.XrRuntimeProbe

/**
 * Single-activity native OpenStream app. Runs edge-to-edge with the *status*
 * bar hidden — that removes the tablet taskbar/notification handle the user
 * disliked at the top — while the navigation bar stays live so the one-swipe
 * Home gesture keeps working. Full immersive (hiding the nav bar too) made
 * Android swallow the first upward swipe to reveal the bar transiently, which
 * is exactly why "swipe up to exit" felt broken. Escape is always available:
 * swipe up to Home (back to OpenPanel) and the back gesture from Discover.
 *
 * On Googlebook/desktop windowing the window is a normal resizable desktop
 * window: no orientation lock, system bars left alone, keyboard shortcuts,
 * full-screen toggle and picture-in-picture come from [PlaybackWindowHost].
 * Each window is its own instance ("New window", Ctrl+N), and local video or
 * audio plays when it is opened with OpenStream, picked (Ctrl+O) or dropped.
 */
class NativeAppActivity : ComponentActivity(), PlaybackWindowHost {
    private val pictureInPictureState = mutableStateOf(false)
    override val inPictureInPicture: State<Boolean> get() = pictureInPictureState
    override val desktopWindowing: Boolean by lazy {
        packageManager.hasSystemFeature(PackageManager.FEATURE_PC)
    }
    // Only a full screen OpenStream requested can be exited with
    // requestFullscreenMode; a window the system opened full screen can't.
    private var fullscreenRequested = false
    override val fullscreenWindow: Boolean get() = fullscreenRequested && !isInMultiWindowMode
    override val canToggleFullscreen: Boolean
        get() = desktopWindowing && Build.VERSION.SDK_INT >= 35 && (isInMultiWindowMode || fullscreenWindow)

    private var playerKeyHandler: ((KeyEvent) -> Boolean)? = null
    private var appKeyHandler: ((KeyEvent) -> Boolean)? = null
    private val swallowedKeyUps = mutableSetOf<Int>()
    private var playbackActive = false
    private var playbackAspect: Rational? = null

    private val television: Boolean by lazy {
        getSystemService(UiModeManager::class.java)?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

    private val localMediaState = mutableStateOf<LocalMedia?>(null)
    override val pendingLocalMedia: State<LocalMedia?> get() = localMediaState
    private var dropPermissions: DragAndDropPermissions? = null
    private var escapeBackInFlight = false
    private val localMediaPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { offerLocalMedia(it, "picked") }
    }

    // TV keeps its existing behavior (Home stops playback); phones, tablets
    // and desktops shrink a playing video into picture-in-picture instead.
    private val pictureInPictureAllowed: Boolean by lazy {
        !television && packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logRecentAbnormalExit()
        Logs.event("app started")
        applyDeviceOrientation()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        @Suppress("DEPRECATION")
        run { window.navigationBarColor = android.graphics.Color.TRANSPARENT }
        if (Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
        if (savedInstanceState == null) handleViewIntent(intent)
        setContent {
            OpenStreamTheme {
                LocalMediaDropZone(enabled = !television, onDrop = ::acceptDrop) {
                    OpenStreamLaunchGate {
                        // Back from Discover leaves the app; Esc never closes the window.
                        OpenStreamApp(onExit = { if (!escapeBackInFlight) finish() })
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleViewIntent(intent)
    }

    // A file manager's "Open with OpenStream" for a video or audio file.
    private fun handleViewIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val type = intent.type ?: runCatching { contentResolver.getType(uri) }.getOrNull()
        if (!LocalMediaPolicy.accepts(uri.scheme, type)) return
        offerLocalMedia(uri, "opened")
    }

    private fun acceptDrop(event: DragEvent): Boolean {
        val clip = event.clipData ?: return false
        val uri = (0 until clip.itemCount).firstNotNullOfOrNull { clip.getItemAt(it).uri } ?: return false
        // Cross-app drops need the drag's read grant; it lasts until the next drop.
        dropPermissions?.release()
        dropPermissions = requestDragAndDropPermissions(event)
        offerLocalMedia(uri, "dropped")
        return true
    }

    private fun offerLocalMedia(uri: Uri, origin: String) {
        val name = runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull() ?: uri.lastPathSegment?.substringAfterLast('/')
        localMediaState.value = LocalMedia(uri.toString(), name?.takeIf { it.isNotBlank() } ?: "Local file")
        // No file name or path in the log.
        Logs.event("local media $origin")
    }

    override fun consumeLocalMedia() {
        localMediaState.value = null
    }

    override fun pickLocalMedia() {
        if (television) return
        runCatching { localMediaPicker.launch(arrayOf("video/*", "audio/*")) }
            .onFailure { Logs.warn("file picker unavailable: ${it.message}") }
    }

    override val canOpenNewWindow: Boolean get() = desktopWindowing

    override fun openNewWindow() {
        if (!canOpenNewWindow) return
        runCatching {
            startActivity(
                Intent(this, NativeAppActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT,
                ),
            )
        }.onSuccess { Logs.event("new window opened") }
            .onFailure { Logs.warn("new window unavailable: ${it.message}") }
    }

    private fun applyDeviceOrientation() {
        val runtime = XrRuntimeProbe.inspect(this)
        val preference = DevicePresentationPolicy.orientation(
            smallestWidthDp = resources.configuration.smallestScreenWidthDp,
            immersiveRuntime = runtime.immersiveRuntimeAvailable(),
            desktopWindowing = desktopWindowing || isInMultiWindowMode,
        )
        requestedOrientation = when (preference) {
            OrientationPreference.SYSTEM -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            OrientationPreference.USER_LANDSCAPE -> ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
        }
        Logs.event("device presentation: ${preference.name.lowercase()} · ${runtime.runtimeLabel()}")
    }

    private fun logRecentAbnormalExit() {
        if (Build.VERSION.SDK_INT < 30) return
        val activityManager = getSystemService(ActivityManager::class.java)
        val lastExit = activityManager.getHistoricalProcessExitReasons(packageName, 0, 1).firstOrNull() ?: return
        when (lastExit.reason) {
            android.app.ApplicationExitInfo.REASON_CRASH,
            android.app.ApplicationExitInfo.REASON_CRASH_NATIVE,
            android.app.ApplicationExitInfo.REASON_ANR,
            -> Logs.warn("previous app session ended abnormally (reason ${lastExit.reason})")
            else -> Unit
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    override fun setPlayerKeyHandler(handler: ((KeyEvent) -> Boolean)?) {
        playerKeyHandler = handler
    }

    override fun setAppKeyHandler(handler: ((KeyEvent) -> Boolean)?) {
        appKeyHandler = handler
    }

    // Activity-level routing: PlayerView (an Android view inside Compose)
    // takes key focus during playback, so Compose modifiers alone never see
    // Space or the arrows there. The matching key-up is swallowed too.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                val handled = windowShortcut(event) || playerKeyHandler?.invoke(event) == true ||
                    appKeyHandler?.invoke(event) == true
                if (handled) {
                    swallowedKeyUps += event.keyCode
                    return true
                }
            }
            KeyEvent.ACTION_UP -> if (swallowedKeyUps.remove(event.keyCode)) return true
        }
        if (super.dispatchKeyEvent(event)) return true
        // Desktop images don't map Esc to Back. An Esc nothing else used
        // (text fields clear themselves first) closes the screen like Back.
        if (event.keyCode == KeyEvent.KEYCODE_ESCAPE && event.action == KeyEvent.ACTION_UP &&
            !event.isCanceled && event.hasNoModifiers()
        ) {
            escapeBackInFlight = true
            try {
                onBackPressedDispatcher.onBackPressed()
            } finally {
                escapeBackInFlight = false
            }
            return true
        }
        return false
    }

    // Ctrl+N new window, Ctrl+O open a file: work on every screen, player included.
    private fun windowShortcut(event: KeyEvent): Boolean {
        if (television || !event.isCtrlPressed || event.isAltPressed || event.isMetaPressed || event.isShiftPressed) {
            return false
        }
        return when (event.keyCode) {
            KeyEvent.KEYCODE_N -> canOpenNewWindow.also { if (it) openNewWindow() }
            KeyEvent.KEYCODE_O -> true.also { pickLocalMedia() }
            else -> false
        }
    }

    // Meta+/ (Keyboard Shortcuts Helper) lists what OpenStream understands.
    override fun onProvideKeyboardShortcuts(data: MutableList<KeyboardShortcutGroup>, menu: Menu?, deviceId: Int) {
        super.onProvideKeyboardShortcuts(data, menu, deviceId)
        fun shortcut(label: String, keyCode: Int, modifiers: Int = 0) = KeyboardShortcutInfo(label, keyCode, modifiers)
        val ctrl = KeyEvent.META_CTRL_ON
        data += KeyboardShortcutGroup(
            "OpenStream",
            buildList {
                add(shortcut("Search", KeyEvent.KEYCODE_F, ctrl))
                add(shortcut("Discover", KeyEvent.KEYCODE_1, ctrl))
                add(shortcut("Library", KeyEvent.KEYCODE_2, ctrl))
                add(shortcut("Live TV", KeyEvent.KEYCODE_3, ctrl))
                add(shortcut("Settings", KeyEvent.KEYCODE_COMMA, ctrl))
                add(shortcut("Open a video or audio file", KeyEvent.KEYCODE_O, ctrl))
                if (canOpenNewWindow) add(shortcut("New window", KeyEvent.KEYCODE_N, ctrl))
                add(shortcut("Back / close", KeyEvent.KEYCODE_ESCAPE))
            },
        )
        data += KeyboardShortcutGroup(
            "Player",
            listOf(
                shortcut("Play / pause", KeyEvent.KEYCODE_SPACE),
                shortcut("Play / pause", KeyEvent.KEYCODE_K),
                shortcut("Back 10 seconds", KeyEvent.KEYCODE_DPAD_LEFT),
                shortcut("Forward 10 seconds", KeyEvent.KEYCODE_DPAD_RIGHT),
                shortcut("Mute", KeyEvent.KEYCODE_M),
                shortcut("Full screen", KeyEvent.KEYCODE_F),
                shortcut("Picture-in-picture", KeyEvent.KEYCODE_P),
            ),
        )
    }

    override fun updatePlayback(playing: Boolean, videoWidth: Int, videoHeight: Int) {
        playbackActive = playing
        if (videoWidth > 0 && videoHeight > 0) playbackAspect = Rational(videoWidth, videoHeight)
        if (!pictureInPictureAllowed || Build.VERSION.SDK_INT < 31) return
        runCatching { setPictureInPictureParams(pictureInPictureParams()) }
            .onFailure { Logs.warn("picture-in-picture params rejected: ${it.message}") }
    }

    override fun enterPictureInPicture(): Boolean {
        if (!pictureInPictureAllowed || isInPictureInPictureMode) return false
        return runCatching { enterPictureInPictureMode(pictureInPictureParams()) }
            .onFailure { Logs.warn("picture-in-picture unavailable: ${it.message}") }
            .getOrDefault(false)
    }

    override fun toggleFullscreenWindow() {
        if (!canToggleFullscreen || Build.VERSION.SDK_INT < 35) return
        if (isInMultiWindowMode) {
            requestFullscreenMode(Activity.FULLSCREEN_MODE_REQUEST_ENTER, null)
            fullscreenRequested = true
        } else {
            requestFullscreenMode(Activity.FULLSCREEN_MODE_REQUEST_EXIT, null)
            fullscreenRequested = false
        }
        Logs.event("desktop full screen ${if (fullscreenRequested) "requested" else "left"}")
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        // Back in a freeform window (caption-bar button, Esc, …): our full screen is over.
        if (isInMultiWindowMode) fullscreenRequested = false
    }

    private fun pictureInPictureParams(): PictureInPictureParams =
        PictureInPictureParams.Builder().apply {
            // PiP accepts 1:2.39 … 2.39:1; ultra-wide masters fall back to the default.
            playbackAspect?.takeIf { it.toFloat() in 0.42f..2.39f }?.let(::setAspectRatio)
            if (Build.VERSION.SDK_INT >= 31) {
                setAutoEnterEnabled(playbackActive)
                setSeamlessResizeEnabled(true)
            }
        }.build()

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // API 31+ auto-enters from the params above; older releases need the call.
        if (Build.VERSION.SDK_INT < 31 && playbackActive) enterPictureInPicture()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pictureInPictureState.value = isInPictureInPictureMode
        Logs.event("picture-in-picture ${if (isInPictureInPictureMode) "entered" else "left"}")
    }

    private fun hideSystemBars() {
        // Desktop windows keep the status bar, caption bar and taskbar.
        if (desktopWindowing) return
        @Suppress("DEPRECATION")
        run { window.navigationBarColor = android.graphics.Color.TRANSPARENT }
        if (Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
        if (Build.VERSION.SDK_INT >= 30) {
            window.insetsController?.let { controller ->
                // Hide the status bar only (kills the top notification/taskbar
                // handle) and leave the navigation bar shown so the gesture
                // Home swipe still works in a single motion — hiding the nav
                // bar put the app in immersive-sticky, where the first upward
                // swipe just peeks the bar back instead of going Home, which
                // is what broke "swipe up to exit".
                controller.hide(WindowInsets.Type.statusBars())
                controller.show(WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
        }
    }
}
