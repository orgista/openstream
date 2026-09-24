import Foundation

enum AppleTrailerSoundBridge {
    static func toggledState(from isMuted: Bool) -> Bool {
        !isMuted
    }

    static func javascriptCommand(isMuted: Bool) -> String {
        "window.setTrailerMuted(\(isMuted ? "true" : "false"));"
    }

    static func accessibilityLabel(isMuted: Bool) -> String {
        isMuted ? "Turn trailer sound on" : "Mute trailer"
    }

    static func accessibilityValue(isMuted: Bool) -> String {
        isMuted ? "Muted" : "Sound on"
    }
}

enum AppleYouTubePreviewHTML {
    /// `allowsSound` lifts the muted-only rule for a host whose web view does
    /// not take over the device's audio session — the Mac hero, whose mute
    /// button is how a viewer asks to hear it. Every other caller stays muted.
    ///
    /// `layoutScale` lays the player out that many times larger in CSS pixels
    /// and scales it back down from its top-left corner, so it draws in
    /// exactly the same place and size while YouTube, which picks its stream
    /// from the player's own size, picks a sharper one
    /// (`AppleTrailerPreviewPolicy.macLayoutScale`).
    static func document(
        embedURL: URL, startsPlaying: Bool, isLandscape: Bool = false, startsMuted: Bool = true, allowsSound: Bool = false,
        layoutScale: Int = 1
    ) -> String {
        let requiresMutedPlayback = ApplePlaybackSessionPolicy.trailer.requiresMutedWebPlayback && !allowsSound
        let effectiveMuted = requiresMutedPlayback || startsMuted
        var components = URLComponents(url: embedURL, resolvingAgainstBaseURL: false)
        let existingItems = components?.queryItems ?? []
        components?.queryItems = existingItems.filter { !["mute", "autoplay", "playsinline"].contains($0.name) }
            + [URLQueryItem(name: "mute", value: effectiveMuted ? "1" : "0"),
               URLQueryItem(name: "autoplay", value: startsPlaying ? "1" : "0"),
               URLQueryItem(name: "playsinline", value: "1")]
        let safeSource = htmlEscaped((components?.url ?? embedURL).absoluteString)
        let safeAutoplay = startsPlaying ? 1 : 0
        let safeDesiredPlaying = startsPlaying ? "true" : "false"
        let scale = min(max(layoutScale, 1), 3)
        let scaledLayout = scale == 1 ? "" : """

        iframe{width:\(scale * 100)%;height:\(scale * 100)%;transform:scale(\(1 / Double(scale)));transform-origin:0 0}
        """
        return """
        <!doctype html>
        <html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
        html,body{position:relative;margin:0;width:100%;height:100%;background:transparent;overflow:hidden}
        iframe{position:absolute;inset:0;margin:0;width:100%;height:100%;background:#000;border:0;opacity:1;pointer-events:none}
        body.ready iframe{opacity:1;transition:opacity .12s linear}
        @media(prefers-reduced-motion:reduce){iframe{transition:none}}\(scaledLayout)
        </style>
        </head><body>
        <iframe id="player" src="\(safeSource)" allow="autoplay; encrypted-media" referrerpolicy="strict-origin-when-cross-origin"></iframe>
        <script>
        var player = null;
        const requiresMutedPlayback = \(requiresMutedPlayback ? "true" : "false");
        var desiredMuted = \(effectiveMuted ? "true" : "false");
        var lastPlayerWidth = 0, lastPlayerHeight = 0;
        var layoutScale = \(scale);
        var desiredPlaying = \(safeDesiredPlaying);
        var playerReady = false;
        var actualPlayerState = null;
        var captionSuppressionAttempts = 0;
        var syncAttempts = 0;
        var revealTimer = null;
        var revealWatchdogTimer = null;
        var hasSeenPlaying = false;
        var hasRevealed = false;
        var landscape = \(isLandscape ? "true" : "false");
        var playingSince = null;
        var playbackGeneration = 0;
        var previewCapTimer = null;
        var previewCapDeadlineTimer = null;
        var previewEnding = false;
        var previewCapSeconds = 60; // owner 2026-09-24: give each hero page about a minute of trailer
        // Ends early enough for the 0.6 s crossfade back to the art to finish
        // over live frames, before YouTube can paint its end screen.
        var previewHideLeadSeconds = 0.8;
        var api = document.createElement('script');
        api.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(api);

        function notifyNative(state, mutedOverride, errorCode) {
          try {
            var muted = typeof mutedOverride === 'boolean'
              ? mutedOverride
              : (player && typeof player.isMuted === 'function' ? player.isMuted() : desiredMuted);
            var mediaTime = player && typeof player.getCurrentTime === 'function' ? player.getCurrentTime() : 0;
            var quality = player && typeof player.getPlaybackQuality === 'function' ? player.getPlaybackQuality() : '';
            var payload = {state: state, muted: Boolean(muted), mediaTime: mediaTime, quality: quality};
            if (typeof errorCode === 'number') payload.errorCode = errorCode;
            window.webkit.messageHandlers.trailerState.postMessage(payload);
          } catch (_) {}
        }

        function applyAudioPreference() {
          if (!player || typeof player.setVolume !== 'function') return;
          if (desiredMuted) {
            if (typeof player.mute === 'function') player.mute();
            player.setVolume(0);
          } else {
            if (typeof player.unMute === 'function') player.unMute();
            player.setVolume(100);
          }
        }

        function refreshAudioState() {
          if (!player || !playerReady) return;
          applyAudioPreference();
        }

        function clearRevealTimers() {
          if (revealTimer) {
            clearTimeout(revealTimer);
            revealTimer = null;
          }
          if (revealWatchdogTimer) {
            clearTimeout(revealWatchdogTimer);
            revealWatchdogTimer = null;
          }
        }

        function clearPreviewCapTimers() {
          if (previewCapTimer) {
            clearInterval(previewCapTimer);
            previewCapTimer = null;
          }
          if (previewCapDeadlineTimer) {
            clearTimeout(previewCapDeadlineTimer);
            previewCapDeadlineTimer = null;
          }
        }

        function hidePlayer() {
          clearRevealTimers();
          clearPreviewCapTimers();
          hasRevealed = false;
          hasSeenPlaying = false;
          playingSince = null;
          document.body.classList.remove('ready');
        }

        function resizePlayer() {
          if (!player || !playerReady || typeof player.setSize !== 'function') return;
          var width = Math.round(window.innerWidth * layoutScale), height = Math.round(window.innerHeight * layoutScale);
          if (width === lastPlayerWidth && height === lastPlayerHeight) return;
          lastPlayerWidth = width; lastPlayerHeight = height;
          player.setSize(width, height);
        }

        function revealPlayer(reason) {
          if (!desiredPlaying || !playerReady || hasRevealed || !hasSeenPlaying) return;
          if (Date.now() - playingSince < (landscape ? 3200 : 900)) return;
          if (reason === 'watchdog') console.log('[OpenStream] trailer reveal watchdog: PLAYING was seen without a reveal');
          resizePlayer();
          document.body.classList.add('ready');
          hasRevealed = true;
          clearRevealTimers();
          notifyNative('revealed');
        }

        function revealAfterPlaybackStarts() {
          if (!desiredPlaying || !playerReady || hasRevealed) return;
          if (revealTimer) return;
          var reveal = function() {
            if (hasSeenPlaying) revealPlayer('playing-delay');
            revealTimer = null;
          };
          if (landscape) {
            revealTimer = setTimeout(reveal, 3200);
          } else {
            revealTimer = setTimeout(function() { reveal(); }, 900);
          }
        }

        window.setTrailerLandscape = function(value) {
          if (landscape === Boolean(value)) return;
          landscape = Boolean(value);
          // Keep the same player and playback position when rotating, but
          // conceal it while the new geometry and reveal delay settle.
          clearRevealTimers();
          hasRevealed = false;
          document.body.classList.remove('ready');
          notifyNative('concealed');
          if (hasSeenPlaying && desiredPlaying) {
            playingSince = Date.now();
            revealAfterPlaybackStarts();
          }
        };

        function startPlayback() {
          hidePlayer();
          playbackGeneration += 1;
          previewEnding = false;
          applyAudioPreference();
          player.playVideo();
          // An autoplaying iframe can reach PLAYING before onReady. playVideo
          // then emits no new state transition, so seed the reveal gate here.
          if (typeof player.getPlayerState === 'function' && player.getPlayerState() === YT.PlayerState.PLAYING) {
            hasSeenPlaying = true;
            playingSince = Date.now();
            revealAfterPlaybackStarts();
          }
          previewCapTimer = setInterval(function() {
            if (!desiredPlaying || previewEnding || !player || !playerReady || typeof player.getCurrentTime !== 'function') return;
            var duration = typeof player.getDuration === 'function' ? player.getDuration() : 0;
            var cap = duration > 0 ? Math.min(duration, previewCapSeconds) : previewCapSeconds;
            if (player.getCurrentTime() >= cap - previewHideLeadSeconds) finishPreview();
          }, 250);
          // Keep the cap independent of YouTube's current-time reporting. The
          // IFrame API can briefly return a stale value while the player is
          // buffering or resizing, but the preview must still end at 45 s.
          previewCapDeadlineTimer = setTimeout(finishPreview, (previewCapSeconds - previewHideLeadSeconds) * 1000);
          revealWatchdogTimer = setTimeout(function() {
            if (hasSeenPlaying && !hasRevealed) revealPlayer('watchdog');
            revealWatchdogTimer = null;
          }, 6000);
        }

        function finishPreview() {
          if (!desiredPlaying || previewEnding) return;
          previewEnding = true;
          desiredPlaying = false;
          hidePlayer();
          // Hide HTML immediately, then let native acknowledge alpha == 0
          // before issuing pauseVideo (which can display related videos).
          notifyNative('ended');
        }

        window.completeTrailerEnd = function() {
          if (desiredPlaying) return;
          hidePlayer();
          if (player && typeof player.pauseVideo === 'function') player.pauseVideo();
        };

        function scheduleEndCleanup(hidePlayer) {
          setTimeout(hidePlayer, 650);
        }

        window.setTrailerMuted = function(isMuted) {
          desiredMuted = requiresMutedPlayback || Boolean(isMuted);
          applyAudioPreference();
          refreshAudioState();
          // The IFrame API updates its internal mute state asynchronously.
          // Report the requested state here so native UI does not immediately
          // overwrite a user's tap with the previous player state.
          notifyNative(desiredMuted ? 'muted' : 'unmuted', desiredMuted);
          return desiredMuted;
        };

        window.setTrailerPlaying = function(isPlaying) {
          desiredPlaying = Boolean(isPlaying);
          if (!player || !playerReady) return desiredPlaying;
          if (desiredPlaying) {
            startPlayback();
          } else {
            hidePlayer();
            player.pauseVideo();
            notifyNative('paused');
          }
          return desiredPlaying;
        };

        window.restartTrailer = function() {
          desiredPlaying = true;
          if (!player || !playerReady) return true;
          clearPreviewCapTimers();
          previewEnding = false;
          if (typeof player.seekTo === 'function') player.seekTo(0, true);
          startPlayback();
          return true;
        };

        function suppressCaptions() {
          if (!player || captionSuppressionAttempts >= 4) return;
          captionSuppressionAttempts += 1;
          try { player.setOption('captions', 'track', {}); } catch (_) {}
          try {
            if (typeof player.unloadModule === 'function') player.unloadModule('captions');
          } catch (_) {}
        }

        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            playerVars: {
              autoplay: \(safeAutoplay),
              mute: \(effectiveMuted ? 1 : 0),
              playsinline: 1,
              controls: 0,
              disablekb: 1,
              modestbranding: 1,
              showinfo: 0,
              iv_load_policy: 3,
              enablejsapi: 1,
              rel: 0,
              fs: 0,
              origin: 'https://openstream.app'
            },
            events: {
              'onReady': function(event) {
                  suppressCaptions();
                  setTimeout(suppressCaptions, 350);
                  playerReady = true;
                  applyAudioPreference();
                  resizePlayer();
                  hidePlayer();
                  if (desiredPlaying) {
                    startPlayback();
                  }
                  notifyNative('ready');
              },
              'onStateChange': function(event) {
                actualPlayerState = event.data;
                notifyNative('iframe-state-' + event.data);
                if (event.data === YT.PlayerState.PLAYING) {
                  if (!desiredPlaying) { hidePlayer(); return; }
                  if (!hasSeenPlaying) playingSince = Date.now();
                  hasSeenPlaying = true;
                  suppressCaptions();
                  resizePlayer();
                  revealAfterPlaybackStarts();
                  notifyNative('playing');
                } else if (event.data === YT.PlayerState.PAUSED) {
                  hidePlayer();
                  notifyNative('paused');
                } else if (event.data === YT.PlayerState.ENDED) {
                  desiredPlaying = false;
                  hidePlayer();
                  notifyNative('ended');
                  // A second cleanup covers a late iframe end-screen paint;
                  // never let an old callback conceal a newly replayed video.
                  var endedGeneration = playbackGeneration;
                  scheduleEndCleanup(function() {
                    if (playbackGeneration === endedGeneration && !desiredPlaying) {
                      document.body.classList.remove('ready');
                    }
                  });
                }
              },
              'onApiChange': function() {
                suppressCaptions();
                refreshAudioState();
                notifyNative('apiChange');
              },
              'onAutoplayBlocked': function() {
              hidePlayer();
              notifyNative('autoplay-blocked');
              },
              'onError': function(event) {
                desiredPlaying = false;
                hidePlayer();
                notifyNative('error', true, event.data);
              }
            }
          });
        }

        window.addEventListener('resize', resizePlayer);
        window.setInterval(function() {
          if (!playerReady || syncAttempts > 4 || actualPlayerState === null) return;
          syncAttempts += 1;
          refreshAudioState();
          if (actualPlayerState === YT.PlayerState.PLAYING) {
            notifyNative('playing');
          } else if (actualPlayerState === YT.PlayerState.PAUSED) {
            notifyNative('paused');
          } else if (actualPlayerState === YT.PlayerState.ENDED) {
            notifyNative('ended');
          }
        }, 800);
        </script>
        </body></html>
        """
    }

    /// Injected into every frame of the Mac hero's web view, it acts only in
    /// YouTube's own player page, which the host page cannot reach across
    /// origins (macOS WebKit runs user scripts there):
    /// - the play/pause glyph YouTube flashes in the middle of the picture
    ///   (it showed at the crossfade, N31) and its caption window never draw;
    /// - it reports the player page's size and where its `<video>` is drawn
    ///   whenever either changes (`geometry`). YouTube re-lays its video out
    ///   a few frames after the page is resized, so the host waits for this
    ///   to settle at the web view's new size before the art fades (N31: the
    ///   picture came in at the art's size, then grew once the cover was going).
    static let macPlayerFrameScript = """
    (function() {
      if (!/(^|\\.)youtube(-nocookie)?\\.com$/.test(location.hostname)) return;
      var style = document.createElement('style');
      style.textContent = '[class^="player-controls"],[class*=" player-controls"],.ytp-bezel,.ytp-bezel-text-wrapper,.ytp-caption-window-container,.caption-window{display:none!important}';
      (document.head || document.documentElement).appendChild(style);
      var last = '';
      function report() {
        var video = document.querySelector('video');
        var box = video ? video.getBoundingClientRect() : null;
        var geometry = {state: 'geometry', frame: [innerWidth, innerHeight],
          video: box ? [box.left, box.top, box.width, box.height] : null,
          source: video ? [video.videoWidth, video.videoHeight] : null};
        var key = JSON.stringify(geometry);
        if (key === last) return;
        last = key;
        try { window.webkit.messageHandlers.trailerState.postMessage(geometry); } catch (_) {}
      }
      addEventListener('resize', report);
      setInterval(report, 50);
    })();
    """

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
