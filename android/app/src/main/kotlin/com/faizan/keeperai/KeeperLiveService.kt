package com.faizan.keeperai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs

class KeeperLiveService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var windowManager: WindowManager
    private var overlayRoot: LinearLayout? = null
    private var overlayPanel: LinearLayout? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var statusText: TextView? = null
    private var answerText: TextView? = null
    private var questionInput: EditText? = null

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null

    @Volatile
    private var pendingQuestion: String? = null

    override fun onCreate() {
        super.onCreate()
        currentInstance = this
        isRunning = true
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        createOverlay()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (mediaProjection == null && intent?.action == ACTION_START) {
            val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
            val resultData: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
            }
            if (resultCode == 0 || resultData == null) {
                showStatus("Screen permission was not granted.")
                stopSelf()
                return START_NOT_STICKY
            }
            startProjection(resultCode, resultData)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startProjection(resultCode: Int, data: Intent) {
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = manager.getMediaProjection(resultCode, data)
        if (projection == null) {
            showStatus("Could not start screen sharing.")
            stopSelf()
            return
        }
        mediaProjection = projection

        projection.registerCallback(
            object : MediaProjection.Callback() {
                override fun onStop() {
                    mainHandler.post {
                        showStatus("Screen sharing stopped.")
                        stopSelf()
                    }
                }
            },
            mainHandler,
        )

        val metrics = resources.displayMetrics
        val width = metrics.widthPixels.coerceAtLeast(1)
        val height = metrics.heightPixels.coerceAtLeast(1)
        val density = metrics.densityDpi

        captureThread = HandlerThread("KeeperLiveCapture").also { it.start() }
        captureHandler = Handler(captureThread!!.looper)
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 3)
        imageReader?.setOnImageAvailableListener({ reader ->
            val image = try {
                reader.acquireLatestImage()
            } catch (_: Exception) {
                null
            } ?: return@setOnImageAvailableListener

            val question = pendingQuestion
            if (question == null) {
                image.close()
                return@setOnImageAvailableListener
            }
            pendingQuestion = null

            try {
                val file = saveImage(image, width, height)
                mainHandler.post {
                    overlayRoot?.visibility = View.VISIBLE
                    showStatus("Keeper is understanding this screen…")
                }
                KeeperLiveChannel.sendScreen(file.absolutePath, question)
            } catch (_: Exception) {
                mainHandler.post {
                    overlayRoot?.visibility = View.VISIBLE
                    showStatus("Could not read this screen. Tap and retry.")
                }
            } finally {
                image.close()
            }
        }, captureHandler)

        virtualDisplay = projection.createVirtualDisplay(
            "KeeperLiveDisplay",
            width,
            height,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null,
            captureHandler,
        )
        showStatus("Ready • Tap K, then Read screen")
    }

    private fun saveImage(image: Image, width: Int, height: Int): File {
        val plane = image.planes.first()
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * width
        val paddedWidth = width + rowPadding / pixelStride
        val padded = Bitmap.createBitmap(paddedWidth, height, Bitmap.Config.ARGB_8888)
        padded.copyPixelsFromBuffer(buffer)
        val cropped = Bitmap.createBitmap(padded, 0, 0, width, height)

        val directory = File(cacheDir, "keeper_live").apply { mkdirs() }
        directory.listFiles()
            ?.sortedByDescending { it.lastModified() }
            ?.drop(3)
            ?.forEach { it.delete() }
        val file = File(directory, "screen_${System.currentTimeMillis()}.png")
        FileOutputStream(file).use { stream ->
            cropped.compress(Bitmap.CompressFormat.PNG, 96, stream)
        }
        cropped.recycle()
        padded.recycle()
        return file
    }

    private fun requestCapture() {
        if (mediaProjection == null || pendingQuestion != null) {
            showStatus("Keeper Live is busy. Please wait.")
            return
        }
        val question = questionInput?.text?.toString()?.trim().orEmpty().ifEmpty {
            "Read the current screen carefully. Explain what is important and tell me the most useful next action. If it is a question, solve it clearly. If it is a form or website, guide me without inventing personal information."
        }
        hideKeyboardAndReleaseFocus()
        showStatus("Capturing current screen…")
        answerText?.text = ""
        overlayRoot?.visibility = View.INVISIBLE
        mainHandler.postDelayed({ pendingQuestion = question }, 220)
    }

    fun showStatus(message: String) {
        mainHandler.post {
            statusText?.text = message
            if (overlayRoot?.visibility != View.VISIBLE) {
                overlayRoot?.visibility = View.VISIBLE
            }
        }
    }

    fun showAnswer(answer: String) {
        mainHandler.post {
            statusText?.text = "Answer ready"
            answerText?.text = answer.ifBlank { "Keeper could not find an answer." }
            overlayPanel?.visibility = View.VISIBLE
            setOverlayFocusable(true)
        }
    }

    private fun createOverlay() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.END
            setPadding(dp(4), dp(4), dp(4), dp(4))
        }
        val panel = buildPanel()
        root.addView(panel)

        val bubble = TextView(this).apply {
            text = "K"
            textSize = 22f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            background = roundedDrawable(0xFF7067F7.toInt(), dp(22))
            elevation = dp(10).toFloat()
        }
        root.addView(
            bubble,
            LinearLayout.LayoutParams(dp(56), dp(56)).apply {
                gravity = Gravity.END
                topMargin = dp(8)
            },
        )

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.displayMetrics.widthPixels - dp(72)
            y = dp(180)
        }

        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        bubble.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (event.rawX - downX).toInt()
                    params.y = startY + (event.rawY - downY).toInt()
                    try {
                        windowManager.updateViewLayout(root, params)
                    } catch (_: Exception) {
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (
                        abs(event.rawX - downX) < dp(8).toFloat() &&
                        abs(event.rawY - downY) < dp(8).toFloat()
                    ) {
                        val opening = panel.visibility != View.VISIBLE
                        panel.visibility = if (opening) View.VISIBLE else View.GONE
                        setOverlayFocusable(opening)
                    }
                    true
                }
                else -> false
            }
        }

        overlayRoot = root
        overlayPanel = panel
        overlayParams = params
        windowManager.addView(root, params)
    }

    private fun buildPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = roundedDrawable(0xF20E1422.toInt(), dp(20), 0xFF3E3978.toInt())
            visibility = View.GONE
            elevation = dp(12).toFloat()
        }

        panel.addView(TextView(this).apply {
            text = "Keeper Live"
            textSize = 17f
            setTextColor(Color.WHITE)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        })

        statusText = TextView(this).apply {
            text = "Ready"
            textSize = 11.5f
            setTextColor(0xFFAAA4FF.toInt())
            setPadding(0, dp(4), 0, dp(10))
        }
        panel.addView(statusText)

        questionInput = EditText(this).apply {
            hint = "Optional: ask about this screen"
            textSize = 13f
            setTextColor(Color.WHITE)
            setHintTextColor(0xFF788094.toInt())
            setSingleLine(false)
            maxLines = 3
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = roundedDrawable(0xFF171D2B.toInt(), dp(13), 0xFF30374A.toInt())
            setOnFocusChangeListener { _, focused ->
                if (focused) setOverlayFocusable(true)
            }
        }
        panel.addView(
            questionInput,
            LinearLayout.LayoutParams(dp(292), WindowManager.LayoutParams.WRAP_CONTENT),
        )

        answerText = TextView(this).apply {
            textSize = 13f
            setTextColor(Color.WHITE)
            setPadding(0, dp(10), 0, 0)
            maxLines = 10
            setTextIsSelectable(true)
        }
        panel.addView(answerText)

        val primaryRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(11), 0, 0)
        }
        primaryRow.addView(
            overlayButton("Read screen", 0xFF7067F7.toInt()) { requestCapture() },
            LinearLayout.LayoutParams(0, dp(42), 1f),
        )
        primaryRow.addView(
            overlayButton("Open Keeper", 0xFF252B3B.toInt()) { openKeeper() },
            LinearLayout.LayoutParams(0, dp(42), 1f).apply { leftMargin = dp(8) },
        )
        panel.addView(primaryRow, LinearLayout.LayoutParams(dp(292), dp(53)))

        val secondaryRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        secondaryRow.addView(
            overlayButton("Copy answer", 0xFF1B2130.toInt()) { copyAnswer() },
            LinearLayout.LayoutParams(0, dp(38), 1f),
        )
        secondaryRow.addView(
            overlayButton("Hide", 0xFF1B2130.toInt()) {
                panel.visibility = View.GONE
                hideKeyboardAndReleaseFocus()
            },
            LinearLayout.LayoutParams(0, dp(38), 1f).apply { leftMargin = dp(7) },
        )
        secondaryRow.addView(
            overlayButton("Stop", 0xFF51262D.toInt()) { stopSelf() },
            LinearLayout.LayoutParams(0, dp(38), 1f).apply { leftMargin = dp(7) },
        )
        panel.addView(secondaryRow, LinearLayout.LayoutParams(dp(292), dp(38)))
        return panel
    }

    private fun overlayButton(label: String, color: Int, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            textSize = 11.5f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            background = roundedDrawable(color, dp(12))
            setOnClickListener { action() }
        }
    }

    private fun setOverlayFocusable(focusable: Boolean) {
        val root = overlayRoot ?: return
        val params = overlayParams ?: return
        params.flags = if (focusable) {
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        } else {
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        }
        try {
            windowManager.updateViewLayout(root, params)
        } catch (_: Exception) {
        }
    }

    private fun hideKeyboardAndReleaseFocus() {
        questionInput?.clearFocus()
        val input = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        input.hideSoftInputFromWindow(questionInput?.windowToken, 0)
        setOverlayFocusable(false)
    }

    private fun copyAnswer() {
        val answer = answerText?.text?.toString().orEmpty()
        if (answer.isBlank()) {
            showStatus("No answer to copy yet.")
            return
        }
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Keeper Live answer", answer))
        showStatus("Answer copied")
    }

    private fun openKeeper() {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        startActivity(intent)
    }

    private fun roundedDrawable(color: Int, radius: Int, strokeColor: Int? = null): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius.toFloat()
            if (strokeColor != null) setStroke(dp(1), strokeColor)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Keeper Live",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows when Keeper Live is reading your screen"
                setSound(null, null)
                enableVibration(false)
            },
        )
    }

    private fun buildNotification(): android.app.Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = Intent(this, KeeperLiveService::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Keeper Live is active")
            .setContentText("Tap the floating K to read the current screen")
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openPendingIntent)
            .addAction(0, "Stop", stopPendingIntent)
            .build()
    }

    override fun onDestroy() {
        pendingQuestion = null
        imageReader?.setOnImageAvailableListener(null, null)
        imageReader?.close()
        virtualDisplay?.release()
        mediaProjection?.stop()
        captureThread?.quitSafely()
        overlayRoot?.let { root ->
            try {
                windowManager.removeView(root)
            } catch (_: Exception) {
            }
        }
        overlayRoot = null
        currentInstance = null
        isRunning = false
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.faizan.keeperai.action.START_LIVE"
        const val ACTION_STOP = "com.faizan.keeperai.action.STOP_LIVE"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        private const val CHANNEL_ID = "keeper_live_active"
        private const val NOTIFICATION_ID = 7043

        @Volatile
        var isRunning: Boolean = false

        @Volatile
        var currentInstance: KeeperLiveService? = null
    }
}
