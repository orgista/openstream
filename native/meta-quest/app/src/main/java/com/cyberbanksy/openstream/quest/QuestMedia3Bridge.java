package com.cyberbanksy.openstream.quest;

import android.app.Activity;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import androidx.annotation.Keep;
import androidx.media3.common.MediaItem;
import androidx.media3.exoplayer.ExoPlayer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Owns Media3 on Android's main thread while OpenXR renders on its native app thread. */
@Keep
public final class QuestMedia3Bridge {
    private static final String TAG = "OpenStreamQuest";

    private final Activity activity;
    private final Surface surface;
    private ExoPlayer player;
    private volatile boolean released;
    private volatile boolean ready;

    public QuestMedia3Bridge(Activity activity, Surface surface, String uri) {
        this.activity = activity;
        this.surface = surface;
        runOnMainThreadAndWait(() -> {
            if (released) {
                return;
            }
            try {
                player = new ExoPlayer.Builder(activity).build();
                player.setVideoSurface(surface);
                player.setMediaItem(MediaItem.fromUri(uri));
                player.prepare();
                ready = true;
            } catch (RuntimeException error) {
                Log.e(TAG, "Media3 could not prepare the incoming video.", error);
            }
        });
    }

    public boolean isReady() {
        return ready && !released;
    }

    public void play() {
        activity.runOnUiThread(() -> {
            if (player != null && !released) {
                player.play();
            }
        });
    }

    public void pause() {
        activity.runOnUiThread(() -> {
            if (player != null && !released) {
                player.pause();
            }
        });
    }

    public void release() {
        runOnMainThreadAndWait(() -> {
            if (released) {
                return;
            }
            released = true;
            ready = false;
            if (player != null) {
                player.clearVideoSurface(surface);
                player.release();
                player = null;
            }
            surface.release();
        });
    }

    private void runOnMainThreadAndWait(Runnable action) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action.run();
            return;
        }

        CountDownLatch completed = new CountDownLatch(1);
        activity.runOnUiThread(() -> {
            try {
                action.run();
            } finally {
                completed.countDown();
            }
        });
        try {
            if (!completed.await(5, TimeUnit.SECONDS)) {
                Log.e(TAG, "Timed out waiting for the Android media thread.");
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            Log.e(TAG, "Interrupted while waiting for the Android media thread.", interrupted);
        }
    }
}
