package tj.payvand.app.data

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import tj.payvand.core.Limits
import tj.payvand.core.OutgoingMedia
import tj.payvand.core.PayvandApi
import tj.payvand.core.PayvandException
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/** Кэш скачанных вложений на диске: файл качается один раз, что экономит мобильный трафик. */
class MediaCache(private val context: Context) {
    private val dir = File(context.cacheDir, "media").apply { mkdirs() }
    private val locks = ConcurrentHashMap<String, Mutex>()

    private fun fileFor(path: String, name: String?): File {
        val h = MessageDigest.getInstance("SHA-1").digest(path.toByteArray()).joinToString("") { "%02x".format(it) }
        val ext = (name ?: path).substringAfterLast('.', "").filter { it.isLetterOrDigit() }.take(8)
        return File(dir, if (ext.isEmpty()) h else "$h.$ext")
    }

    fun cached(path: String, name: String?): File? = fileFor(path, name).takeIf { it.exists() && it.length() > 0 }

    /** Кладёт только что отправленные байты в кэш, чтобы не скачивать собственный файл обратно. */
    fun put(path: String, name: String?, bytes: ByteArray) { runCatching { fileFor(path, name).writeBytes(bytes) } }

    suspend fun get(api: PayvandApi, path: String, name: String?): File = withContext(Dispatchers.IO) {
        val f = fileFor(path, name)
        locks.getOrPut(path) { Mutex() }.withLock {
            if (!f.exists() || f.length() == 0L) {
                val tmp = File(dir, f.name + ".part")
                tmp.writeBytes(api.downloadMedia(path))
                tmp.renameTo(f)
            }
        }
        f
    }

    fun open(file: File, mime: String?) {
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
        val type = mime?.takeIf { it.contains('/') }
            ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "*/*"
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(Intent.createChooser(i, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    fun clear() { dir.listFiles()?.forEach { it.delete() } }
}

object MediaTools {
    /** Сжимает фото до [maxSide] px по длинной стороне, JPEG. Экономит трафик и место в хранилище. */
    suspend fun compressImage(context: Context, uri: Uri, maxSide: Int = 1600, quality: Int = 82): ByteArray = withContext(Dispatchers.IO) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bmp = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
            ?: throw PayvandException(PayvandException.Code.UNKNOWN)
        val rotation = runCatching {
            context.contentResolver.openInputStream(uri)?.use {
                when (androidx.exifinterface.media.ExifInterface(it).getAttributeInt("Orientation", 1)) { 3 -> 180f; 6 -> 90f; 8 -> 270f; else -> 0f }
            }
        }.getOrNull() ?: 0f
        val scale = maxSide.toFloat() / maxOf(bmp.width, bmp.height)
        if (scale < 1f || rotation != 0f) {
            val m = Matrix().apply { if (scale < 1f) postScale(scale, scale); if (rotation != 0f) postRotate(rotation) }
            bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        }
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
    }

    suspend fun squareAvatar(context: Context, uri: Uri): ByteArray = withContext(Dispatchers.IO) {
        val bytes = compressImage(context, uri, 640, 85)
        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        val side = minOf(bmp.width, bmp.height)
        val sq = Bitmap.createBitmap(bmp, (bmp.width - side) / 2, (bmp.height - side) / 2, side, side)
        ByteArrayOutputStream().also { sq.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
    }

    data class FileInfo(val name: String, val size: Long, val mime: String)

    fun info(context: Context, uri: Uri): FileInfo {
        var name = "file"; var size = -1L
        context.contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) ?: name }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }?.let { if (!c.isNull(it)) size = c.getLong(it) }
            }
        }
        return FileInfo(name, size, context.contentResolver.getType(uri) ?: "application/octet-stream")
    }

    /** Готовит вложение к отправке: фото сжимается, остальное читается как есть (до 20 МБ). */
    suspend fun prepare(context: Context, uri: Uri): OutgoingMedia = withContext(Dispatchers.IO) {
        val info = info(context, uri)
        if (info.mime.startsWith("image/") && info.mime != "image/gif") {
            val bytes = compressImage(context, uri)
            return@withContext OutgoingMedia("image", bytes, info.name.substringBeforeLast('.') + ".jpg", "image/jpeg")
        }
        if (info.size > Limits.MAX_MEDIA_BYTES) throw PayvandException(PayvandException.Code.FILE_TOO_LARGE)
        val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
            val out = ByteArrayOutputStream(); val buf = ByteArray(64 * 1024); var total = 0L
            while (true) {
                val n = input.read(buf); if (n < 0) break
                total += n; if (total > Limits.MAX_MEDIA_BYTES) throw PayvandException(PayvandException.Code.FILE_TOO_LARGE)
                out.write(buf, 0, n)
            }
            out.toByteArray()
        } ?: throw PayvandException(PayvandException.Code.UNKNOWN)
        val isVideo = info.mime.startsWith("video/")
        val duration = if (isVideo) runCatching {
            MediaMetadataRetriever().run { setDataSource(context, uri); val d = extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toInt(); release(); d }
        }.getOrNull() else null
        OutgoingMedia(if (isVideo) "video" else if (info.mime == "image/gif") "image" else "file", bytes, info.name, info.mime, duration)
    }
}

/** Запись голосовых сообщений: AAC в контейнере MP4, моно, 32 кбит/с (~4 КБ на секунду). */
class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L

    fun start(): Boolean = try {
        val f = File(context.cacheDir, "rec-${System.currentTimeMillis()}.m4a")
        @Suppress("DEPRECATION")
        val r = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
        r.setAudioSource(MediaRecorder.AudioSource.MIC)
        r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        r.setAudioChannels(1); r.setAudioSamplingRate(22050); r.setAudioEncodingBitRate(32000)
        r.setOutputFile(f.absolutePath)
        r.prepare(); r.start()
        recorder = r; file = f; startedAt = System.currentTimeMillis()
        true
    } catch (_: Exception) { cancel(); false }

    fun stop(): OutgoingMedia? {
        val r = recorder ?: return null
        val f = file
        val duration = (System.currentTimeMillis() - startedAt).toInt()
        recorder = null; file = null
        val ok = runCatching { r.stop() }.isSuccess
        runCatching { r.release() }
        if (!ok || f == null || duration < 700) { f?.delete(); return null }
        val bytes = f.readBytes(); f.delete()
        return OutgoingMedia("voice", bytes, "voice.m4a", "audio/mp4", duration)
    }

    fun cancel() {
        runCatching { recorder?.stop() }; runCatching { recorder?.release() }
        recorder = null; file?.delete(); file = null
    }
}

/** Один проигрыватель на приложение: одновременно звучит только одно голосовое сообщение. */
class VoicePlayer {
    data class State(val id: String? = null, val playing: Boolean = false, val positionMs: Int = 0, val durationMs: Int = 0)
    val state = MutableStateFlow(State())
    private var player: MediaPlayer? = null

    fun toggle(id: String, file: File) {
        val p = player
        if (p != null && state.value.id == id) {
            if (p.isPlaying) { p.pause(); state.value = state.value.copy(playing = false) }
            else { p.start(); state.value = state.value.copy(playing = true) }
            return
        }
        stop()
        runCatching {
            val np = MediaPlayer()
            np.setDataSource(file.absolutePath)
            np.setOnCompletionListener { stop() }
            np.prepare(); np.start()
            player = np
            state.value = State(id, true, 0, np.duration)
        }.onFailure { stop() }
    }

    fun tick() { player?.let { p -> runCatching { if (p.isPlaying) state.value = state.value.copy(positionMs = p.currentPosition) } } }

    fun stop() {
        runCatching { player?.release() }
        player = null
        state.value = State()
    }
}
