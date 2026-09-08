package com.midoalhashmi.zoltrastream

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// نضيف هنا فقط دعم "صورة داخل صورة" (Picture-in-Picture) عبر قناة
/// ميثود بسيطة مع Flutter (sports_player/pip) — زر اختياري يضغطه
/// المستخدم بنفسه من داخل المشغل، وليس دخولاً تلقائياً عند كل خروج
/// للخلفية (حتى لا نغيّر السلوك الافتراضي الحالي لإيقاف الصوت عند
/// الخروج للخلفية لكل من لا يستخدم PiP). لا شيء آخر يتغيّر في سلوك
/// النشاط الافتراضي.
class MainActivity : FlutterActivity() {
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sports_player/pip")
        pipChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                "enter" -> {
                    val aspectWidth = call.argument<Int>("aspectWidth") ?: 16
                    val aspectHeight = call.argument<Int>("aspectHeight") ?: 9
                    result.success(enterPip(aspectWidth, aspectHeight))
                }
                else -> result.notImplemented()
            }
        }
    }

    // يدخل وضع PiP فعلياً لو مدعوماً على هذا الجهاز/الإصدار. يرجع false
    // بصمت (بدل رمي استثناء) لو غير مدعوم (أقل من Android 8) بدل تعطّل
    // التطبيق — الطرف الفلاتري أصلاً يتحقق من isSupported مسبقاً ويخفي
    // زر PiP كلياً على هذه الأجهزة فلا يصل لهذا الاستدعاء أساساً.
    private fun enterPip(aspectWidth: Int, aspectHeight: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val ratio = Rational(aspectWidth.coerceAtLeast(1), aspectHeight.coerceAtLeast(1))
            val params = PictureInPictureParams.Builder().setAspectRatio(ratio).build()
            enterPictureInPictureMode(params)
        } catch (_: Exception) {
            false
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // نبلّغ الطرف الفلاتري بتغيّر وضع PiP حتى يقدر يوقف "إيقاف
        // التشغيل التلقائي عند الخروج للخلفية" طالما البث ما زال ظاهراً
        // فعلياً داخل نافذة PiP العائمة.
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }
}
