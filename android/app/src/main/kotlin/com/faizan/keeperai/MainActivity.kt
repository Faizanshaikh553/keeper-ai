package com.faizan.keeperai

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.math.min

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.faizan.keeperai/keeper_live",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLive", "stopLive", "isLiveRunning", "showLiveStatus", "showLiveAnswer" -> {
                    result.success(if (call.method == "isLiveRunning") false else null)
                }
                "openGoogleLens" -> result.success(openGoogleLens())
                "printVaultFile" -> {
                    val path = call.argument<String>("path")
                    val fileName = call.argument<String>("fileName") ?: "Keeper file"
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                    if (path.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        result.success(printVaultFile(path, fileName, mimeType))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openGoogleLens(): Boolean {
        val googleApp = "com.google.android.googlequicksearchbox"
        val standaloneLens = packageManager.getLaunchIntentForPackage("com.google.ar.lens")
        val intents = listOfNotNull(
            standaloneLens,
            Intent(Intent.ACTION_VIEW, Uri.parse("googleapp://lens")).apply {
                setPackage(googleApp)
            },
            Intent(Intent.ACTION_VIEW, Uri.parse("https://lens.google.com/")).apply {
                setPackage(googleApp)
            },
            Intent(Intent.ACTION_VIEW, Uri.parse("https://lens.google.com/")),
        )
        for (intent in intents) {
            try {
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
                // Try the next Google Lens entry point.
            }
        }
        return false
    }

    private fun printVaultFile(path: String, fileName: String, mimeType: String): Boolean {
        val source = File(path)
        if (!source.exists() || !source.isFile) return false

        val printable = when {
            mimeType == "application/pdf" -> PrintableType.PDF
            mimeType.startsWith("image/") -> PrintableType.IMAGE
            mimeType == "text/plain" ||
                mimeType == "text/csv" ||
                mimeType == "text/markdown" ||
                mimeType == "application/json" -> PrintableType.TEXT
            else -> return false
        }

        val printManager = getSystemService(Context.PRINT_SERVICE) as? PrintManager
            ?: return false

        return try {
            printManager.print(
                fileName,
                VaultPrintDocumentAdapter(source, fileName, printable),
                PrintAttributes.Builder()
                    .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                    .setColorMode(PrintAttributes.COLOR_MODE_COLOR)
                    .build(),
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private enum class PrintableType {
        PDF,
        IMAGE,
        TEXT,
    }

    private class VaultPrintDocumentAdapter(
        private val source: File,
        private val fileName: String,
        private val type: PrintableType,
    ) : PrintDocumentAdapter() {

        override fun onLayout(
            oldAttributes: PrintAttributes?,
            newAttributes: PrintAttributes,
            cancellationSignal: CancellationSignal,
            callback: LayoutResultCallback,
            extras: android.os.Bundle?,
        ) {
            if (cancellationSignal.isCanceled) {
                callback.onLayoutCancelled()
                return
            }

            val pageCount = if (type == PrintableType.PDF) {
                PrintDocumentInfo.PAGE_COUNT_UNKNOWN
            } else {
                1
            }

            val info = PrintDocumentInfo.Builder(fileName)
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(pageCount)
                .build()

            callback.onLayoutFinished(info, true)
        }

        override fun onWrite(
            pages: Array<PageRange>,
            destination: ParcelFileDescriptor,
            cancellationSignal: CancellationSignal,
            callback: WriteResultCallback,
        ) {
            try {
                if (cancellationSignal.isCanceled) {
                    callback.onWriteCancelled()
                    return
                }

                when (type) {
                    PrintableType.PDF -> copyFile(source, destination)
                    PrintableType.IMAGE -> writeImageAsPdf(source, destination)
                    PrintableType.TEXT -> writeTextAsPdf(source, destination)
                }

                if (cancellationSignal.isCanceled) {
                    callback.onWriteCancelled()
                } else {
                    callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                }
            } catch (e: Exception) {
                callback.onWriteFailed(e.message ?: "Unable to prepare the file for printing.")
            } finally {
                try {
                    destination.close()
                } catch (_: Exception) {
                }
            }
        }

        override fun onFinish() {
            // The decrypted vault copy is temporary and must not remain on disk.
            try {
                if (source.exists()) source.delete()
            } catch (_: Exception) {
            }
        }

        private fun copyFile(source: File, destination: ParcelFileDescriptor) {
            FileInputStream(source).use { input ->
                FileOutputStream(destination.fileDescriptor).use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            }
        }

        private fun writeImageAsPdf(source: File, destination: ParcelFileDescriptor) {
            val bitmap = BitmapFactory.decodeFile(source.absolutePath)
                ?: throw IllegalArgumentException("Unable to decode image.")

            val pdf = android.graphics.pdf.PdfDocument()
            try {
                val pageWidth = 595
                val pageHeight = 842
                val page = pdf.startPage(
                    android.graphics.pdf.PdfDocument.PageInfo.Builder(
                        pageWidth,
                        pageHeight,
                        1,
                    ).create(),
                )

                val canvas = page.canvas
                val margin = 24f
                val availableWidth = pageWidth - margin * 2
                val availableHeight = pageHeight - margin * 2
                val scale = min(
                    availableWidth / bitmap.width.toFloat(),
                    availableHeight / bitmap.height.toFloat(),
                )
                val width = bitmap.width * scale
                val height = bitmap.height * scale
                val left = (pageWidth - width) / 2f
                val top = (pageHeight - height) / 2f

                canvas.drawColor(android.graphics.Color.WHITE)
                canvas.drawBitmap(
                    bitmap,
                    null,
                    RectF(left, top, left + width, top + height),
                    Paint(Paint.ANTI_ALIAS_FLAG),
                )
                pdf.finishPage(page)
                pdf.writeTo(FileOutputStream(destination.fileDescriptor))
            } finally {
                pdf.close()
                bitmap.recycle()
            }
        }

        private fun writeTextAsPdf(source: File, destination: ParcelFileDescriptor) {
            val text = source.readText(Charsets.UTF_8)
            val pdf = android.graphics.pdf.PdfDocument()
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.BLACK
                textSize = 12f
            }

            val pageWidth = 595
            val pageHeight = 842
            val margin = 36f
            val lineHeight = 18f
            val maxWidth = pageWidth - margin * 2
            val lines = mutableListOf<String>()

            text.replace("\r\n", "\n").split('\n').forEach { rawLine ->
                if (rawLine.isEmpty()) {
                    lines.add("")
                    return@forEach
                }

                var remaining = rawLine
                while (remaining.isNotEmpty()) {
                    var end = remaining.length
                    while (end > 1 && paint.measureText(remaining.substring(0, end)) > maxWidth) {
                        end--
                    }
                    lines.add(remaining.substring(0, end))
                    remaining = remaining.substring(end)
                }
            }

            if (lines.isEmpty()) lines.add("")

            try {
                var pageNumber = 0
                var index = 0
                while (index < lines.size) {
                    pageNumber++
                    val page = pdf.startPage(
                        android.graphics.pdf.PdfDocument.PageInfo.Builder(
                            pageWidth,
                            pageHeight,
                            pageNumber,
                        ).create(),
                    )
                    val canvas: Canvas = page.canvas
                    canvas.drawColor(android.graphics.Color.WHITE)
                    var y = margin + paint.textSize
                    while (index < lines.size && y <= pageHeight - margin) {
                        canvas.drawText(lines[index], margin, y, paint)
                        index++
                        y += lineHeight
                    }
                    pdf.finishPage(page)
                }

                pdf.writeTo(FileOutputStream(destination.fileDescriptor))
            } finally {
                pdf.close()
            }
        }
    }
}
