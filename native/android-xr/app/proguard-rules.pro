# jcifs-ng uses reflection for SMB auth negotiation
-keep class jcifs.** { *; }
-dontwarn jcifs.**

# SLF4J optional binding (jcifs-ng references it but Android doesn't ship it)
-dontwarn org.slf4j.impl.StaticLoggerBinder

# ExoPlayer / Media3 loads renderers and extractors reflectively
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# NextLib FFmpeg extension
-keep class io.github.anilbeesetti.nextlib.** { *; }
-dontwarn io.github.anilbeesetti.nextlib.**

# ZXing barcode encoder
-keep class com.google.zxing.** { *; }

# Coil image loader
-keep class coil.** { *; }
-dontwarn coil.**
