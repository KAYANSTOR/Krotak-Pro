package com.kayan.net_app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * WP-S1 — حفظ ملفات في مجلدات عامة ظاهرة لمدير الملفات.
 *
 * - Android 10+ (API 29): عبر MediaStore بلا صلاحية تخزين واسعة، مع
 *   `IS_PENDING` حتى تكتمل الكتابة.
 * - Android 9 فأدنى: كتابة مباشرة إلى المجلد العام
 *   (`WRITE_EXTERNAL_STORAGE` بحد `maxSdkVersion=28` في المانيفست).
 *
 * النواة الحسّية ([sanitizeFileName], [relativeDownloadsPath],
 * [relativePicturesPath], [normalizeSubfolder], [uniqueFile]) نقية بلا `Context`
 * حتى تُختبر على JVM في `android/app/src/test`.
 */
object VisibleStorage {
    /** D2 — اسم المجلد المعتمد (`AppBrand.latinName`). */
    const val FOLDER_NAME = "Krotak Pro"

    const val IMAGE_MIME = "image/png"

    /** ينظّف اسم الملف: يمنع فواصل المسارات والمحارف الممنوعة. */
    fun sanitizeFileName(rawName: String): String {
        val cleaned = rawName
            .replace('\\', '-')
            .replace('/', '-')
            .map { if (it.isISOControl() || it in ILLEGAL_CHARS) '-' else it }
            .joinToString("")
            .trim()
            .trim('.')
        val safe = cleaned.ifBlank { "file" }
        return if (safe.length <= MAX_NAME_LENGTH) safe else safe.take(MAX_NAME_LENGTH)
    }

    /** يُطبّع المجلد الفرعي ويمنع الهروب خارج المجلد العام. */
    fun normalizeSubfolder(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        return raw
            .split('/', '\\')
            .map { it.trim() }
            .filter { it.isNotBlank() && it != "." && it != ".." }
            .map { sanitizeFileName(it) }
            .filter { it.isNotBlank() }
            .joinToString("/")
    }

    /** `Download/Krotak Pro[/sub]` — المسار النسبي المطلوب من MediaStore. */
    fun relativeDownloadsPath(subfolder: String? = null): String =
        listOf(Environment.DIRECTORY_DOWNLOADS, FOLDER_NAME, normalizeSubfolder(subfolder))
            .filter { it.isNotBlank() }
            .joinToString("/")

    /** `Pictures/Krotak Pro[/sub]` (D5). */
    fun relativePicturesPath(subfolder: String? = null): String =
        listOf(Environment.DIRECTORY_PICTURES, FOLDER_NAME, normalizeSubfolder(subfolder))
            .filter { it.isNotBlank() }
            .joinToString("/")

    /** المسار المطلق على Android 9 فأدنى. */
    fun legacyAbsoluteDir(subfolder: String?, pictures: Boolean): File {
        val base = if (pictures) {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        } else {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        }
        return File(File(base, FOLDER_NAME), normalizeSubfolder(subfolder))
    }

    /** يحفظ ملف بيانات عام (تنزيلات). يُرجع المسار/URI الفعلي أو null. */
    fun saveToDownloads(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        subfolder: String? = null,
    ): String? = save(
        context = context,
        bytes = bytes,
        fileName = fileName,
        mimeType = mimeType.ifBlank { "application/octet-stream" },
        subfolder = subfolder,
        pictures = false,
    )

    /** يحفظ صورة PNG في الصور (D5). */
    fun saveImageToPictures(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        subfolder: String? = null,
    ): String? = save(
        context = context,
        bytes = bytes,
        fileName = fileName,
        mimeType = IMAGE_MIME,
        subfolder = subfolder,
        pictures = true,
    )

    private fun save(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        subfolder: String?,
        pictures: Boolean,
    ): String? {
        val safeName = sanitizeFileName(fileName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, bytes, safeName, mimeType, subfolder, pictures)
        } else {
            saveToLegacyDir(bytes, safeName, subfolder, pictures)
        }
    }

    private fun saveViaMediaStore(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        subfolder: String?,
        pictures: Boolean,
    ): String? {
        val resolver = context.contentResolver
        val collection = if (pictures) {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        }
        val relativePath =
            if (pictures) relativePicturesPath(subfolder) else relativeDownloadsPath(subfolder)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: return null
        try {
            resolver.openOutputStream(uri)?.use { stream -> stream.write(bytes) } ?: return null
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    private fun saveToLegacyDir(
        bytes: ByteArray,
        fileName: String,
        subfolder: String?,
        pictures: Boolean,
    ): String? {
        val dir = legacyAbsoluteDir(subfolder, pictures)
        if (!dir.exists() && !dir.mkdirs()) return null
        val file = uniqueFile(dir, fileName)
        file.outputStream().use { stream -> stream.write(bytes) }
        return file.absolutePath
    }

    /** لا يستبدل ملفًا موجودًا — يضيف لاحقة رقمية بدل الكتابة فوقه. */
    fun uniqueFile(dir: File, fileName: String): File {
        val candidate = File(dir, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        var index = 1
        while (index < MAX_UNIQUE_ATTEMPTS) {
            val next = File(dir, "$stem-$index$extension")
            if (!next.exists()) return next
            index += 1
        }
        return File(dir, "$stem-${System.currentTimeMillis()}$extension")
    }

    private const val MAX_NAME_LENGTH = 96
    private const val MAX_UNIQUE_ATTEMPTS = 500
    private val ILLEGAL_CHARS = charArrayOf(':', '*', '?', '"', '<', '>', '|', '\u0000')
}
