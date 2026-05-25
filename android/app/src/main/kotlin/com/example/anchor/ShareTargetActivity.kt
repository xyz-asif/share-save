package com.example.anchor

import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class ShareTargetActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "com.example.anchor/share"
    }

    // I/O off the main thread — content resolver reads can block
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun getRenderMode(): RenderMode = RenderMode.texture
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent
    override fun getDartEntrypointFunctionName(): String = "shareTarget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedData" -> {
                        // File copies happen on a background thread; result posted back on main thread
                        ioExecutor.execute {
                            val data = extractSharedData()
                            mainHandler.post { result.success(data) }
                        }
                    }
                    "close" -> {
                        finish()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFormat(PixelFormat.TRANSLUCENT)
    }

    private fun extractSharedData(): Map<String, Any?> {
        val intent = intent ?: return emptyMap()
        return when (intent.action) {
            Intent.ACTION_SEND -> handleSingleShare(intent, intent.type ?: "")
            Intent.ACTION_SEND_MULTIPLE -> handleMultipleShare(intent, intent.type ?: "")
            else -> emptyMap()
        }
    }

    private fun handleSingleShare(intent: Intent, type: String): Map<String, Any?> {
        if (type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            val isUrl = text.startsWith("http://") || text.startsWith("https://")
            return mapOf("type" to if (isUrl) "link" else "text",
                "text" to text, "subject" to subject, "mimeType" to type)
        }

        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        // Copy content:// URI to a real file path Flutter can read
        val localPath = uri?.let { copyUriToAppStorage(it, type) } ?: uri?.toString()
        val itemType = uriTypeFromMime(type)
        return mapOf("type" to itemType, "uris" to listOf(localPath), "mimeType" to type)
    }

    private fun handleMultipleShare(intent: Intent, type: String): Map<String, Any?> {
        val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        val paths = uris.map { uri ->
            copyUriToAppStorage(uri, type) ?: uri.toString()
        }
        return mapOf("type" to uriTypeFromMime(type), "uris" to paths, "mimeType" to type)
    }

    /**
     * Copies a content:// URI into the app's private files/anchors/ directory
     * and returns the absolute path. Returns null if the copy fails.
     *
     * Flutter's Image.file() cannot read content:// URIs directly — they require
     * Android's ContentResolver which is only available on the native side.
     */
    private fun copyUriToAppStorage(uri: Uri, mimeType: String): String? {
        return try {
            val ext = MimeTypeMap.getSingleton()
                .getExtensionFromMimeType(mimeType) ?: guessExtension(uri) ?: "bin"
            val dir = File(filesDir, "anchors").also { it.mkdirs() }
            val dest = File(dir, "${System.currentTimeMillis()}.$ext")
            contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
            dest.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun guessExtension(uri: Uri): String? {
        val path = uri.path ?: return null
        val dot = path.lastIndexOf('.')
        return if (dot >= 0) path.substring(dot + 1) else null
    }

    private fun uriTypeFromMime(mime: String) = when {
        mime.startsWith("image/") -> "image"
        mime.startsWith("video/") -> "video"
        mime.startsWith("audio/") -> "audio"
        else -> "file"
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
