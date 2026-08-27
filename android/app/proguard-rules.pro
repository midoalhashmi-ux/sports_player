# Flutter video_player (يعتمد داخلياً على AndroidX Media3 / ExoPlayer)
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }

# App Links
-keep class com.llfbandit.app_links.** { *; }

# Obfuscation
-dontwarn androidx.media3.**
