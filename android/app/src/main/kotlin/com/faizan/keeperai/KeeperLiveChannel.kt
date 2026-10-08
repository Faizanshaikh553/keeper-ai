package com.faizan.keeperai

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object KeeperLiveChannel {
    const val CHANNEL_NAME = "com.faizan.keeperai/keeper_live"

    @Volatile
    var channel: MethodChannel? = null

    fun sendScreen(path: String, question: String) {
        Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod(
                "screenCaptured",
                mapOf("path" to path, "question" to question),
            )
        }
    }
}
