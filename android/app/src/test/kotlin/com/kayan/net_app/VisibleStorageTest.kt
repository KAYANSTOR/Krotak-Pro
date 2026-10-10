package com.kayan.net_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * WP-S1 — اختبار نواة [VisibleStorage] على JVM (بلا جهاز):
 * تنظيف الأسماء، تطبيع المجلدات، المسارات النسبية، وعدم الكتابة فوق الملفات.
 */
class VisibleStorageTest {
    @get:Rule
    val temp = TemporaryFolder()

    @Test
    fun sanitizeRejectsPathSeparatorsAndIllegalChars() {
        assertEquals("backup.krt", VisibleStorage.sanitizeFileName("backup.krt"))
        assertEquals("a-b-c", VisibleStorage.sanitizeFileName("a/b\\c"))
        assertEquals("a-b", VisibleStorage.sanitizeFileName("a:b"))
        assertEquals("file", VisibleStorage.sanitizeFileName("   "))
        assertEquals("file", VisibleStorage.sanitizeFileName(".."))
    }

    @Test
    fun sanitizeKeepsArabicAndLimitsLength() {
        assertEquals("إشعار-REF1.png", VisibleStorage.sanitizeFileName("إشعار-REF1.png"))
        val long = VisibleStorage.sanitizeFileName("x".repeat(400))
        assertTrue(long.length <= 96)
    }

    @Test
    fun normalizeSubfolderBlocksEscaping() {
        assertEquals("", VisibleStorage.normalizeSubfolder(null))
        assertEquals("", VisibleStorage.normalizeSubfolder("  "))
        assertEquals("Exports", VisibleStorage.normalizeSubfolder("Exports"))
        assertEquals("a/b", VisibleStorage.normalizeSubfolder("/a//b/"))
        assertEquals("etc/passwd", VisibleStorage.normalizeSubfolder("../../etc/passwd"))
        assertFalse(VisibleStorage.normalizeSubfolder("../..").contains(".."))
    }

    @Test
    fun relativePathsMatchDecisionD1AndD2() {
        assertEquals("Download/Krotak Pro", VisibleStorage.relativeDownloadsPath(null))
        assertEquals("Download/Krotak Pro", VisibleStorage.relativeDownloadsPath(""))
        assertEquals("Download/Krotak Pro/Exports", VisibleStorage.relativeDownloadsPath("Exports"))
        assertEquals("Pictures/Krotak Pro", VisibleStorage.relativePicturesPath(null))
        assertEquals("Pictures/Krotak Pro/Receipts", VisibleStorage.relativePicturesPath("Receipts"))
        assertEquals("Krotak Pro", VisibleStorage.FOLDER_NAME)
    }

    @Test
    fun uniqueFileNeverOverwritesExistingFile() {
        val dir = temp.newFolder("krotak")
        val first = VisibleStorage.uniqueFile(dir, "backup.krt")
        assertEquals("backup.krt", first.name)
        first.writeText("v1")

        val second = VisibleStorage.uniqueFile(dir, "backup.krt")
        assertEquals("backup-1.krt", second.name)
        second.writeText("v2")

        val third = VisibleStorage.uniqueFile(dir, "backup.krt")
        assertEquals("backup-2.krt", third.name)
        assertEquals("v1", first.readText())
    }

    @Test
    fun uniqueFileHandlesNamesWithoutExtension() {
        val dir = temp.newFolder("krotak-noext")
        VisibleStorage.uniqueFile(dir, "receipt").writeText("a")
        assertEquals("receipt-1", VisibleStorage.uniqueFile(dir, "receipt").name)
    }
}
