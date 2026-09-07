# قواعد أساسية آمنة لتصغير الكود (R8) بدون كسر عمل Firebase أو الإضافات
# المستخدمة في التطبيق. التطبيق لا يستخدم أي reflection مخصص على نماذج
# البيانات (التحويل يدوي عبر fromMap)، فلا حاجة لقواعد keep إضافية لها.

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Play Core (يُستخدم داخلياً من Flutter لبعض ميزات التحديث المؤجل)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
