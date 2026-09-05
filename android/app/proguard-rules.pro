# Flutter video_player (يعتمد داخلياً على AndroidX Media3 / ExoPlayer)
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }

# App Links
-keep class com.llfbandit.app_links.** { *; }

# Google Mobile Ads (AdMob) + UMP (نموذج الموافقة) — كانت الإعلانات
# تعمل قبل تفعيل minifyEnabled/shrinkResources (لتصغير حجم APK حسب
# متطلبات Google Play)، لأن هذين القسمين وحدهما بدون قواعد -keep صريحة
# هنا (كل الأقسام الأخرى فوق عندها قواعدها). R8 يحذف/يشوّه كلاسات
# داخلية يعتمد عليها SDK الإعلانات عبر Reflection (خصوصاً في مسار
# الموافقة UMP)، فيفشل تحميل أو عرض الإعلانات بصمت بدون أي كراش ظاهر.
-keep public class com.google.android.gms.ads.** {
   public *;
}
-keep public class com.google.ads.** {
   public *;
}
-keep class com.google.android.ump.** { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.android.ump.**

# Obfuscation
-dontwarn androidx.media3.**
