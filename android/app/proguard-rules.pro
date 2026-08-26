# Flutter MediaKit + mpv
-keep class com.google.android.exoplayer2.** { *; }
-keep class io.github.dalton.** { *; }
-keep class xyz.ian.media.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }

# App Links
-keep class dev.[*].links.** { *; }

# Obfuscation
-dontwarn com.google.android.exoplayer2.**
-dontwarn io.github.dalton.**
-dontwarn xyz.ian.media.**
