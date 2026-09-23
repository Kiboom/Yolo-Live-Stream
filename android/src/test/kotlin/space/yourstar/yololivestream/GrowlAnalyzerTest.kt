package space.yourstar.yololivestream

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class GrowlAnalyzerTest {
    @Test
    fun resampleTo16k_averages48kBlocksAndScalesToUnitRange() {
        val src = FloatArray(480) { if (it % 3 == 0) 32768f else 0f }
        val out = FloatArray(160)

        assertEquals(160, resampleTo16k(src, 480, out))
        out.forEach { assertEquals(1f / 3f, it, 1e-6f) }
    }

    @Test
    fun resampleTo16k_passes16kThroughScaled() {
        val src = FloatArray(160) { it * 100f - 8000f }
        val out = FloatArray(160)

        resampleTo16k(src, 160, out)
        for (i in 0 until 160) assertEquals(src[i] / 32768f, out[i], 1e-6f)
    }

    @Test
    fun resampleTo16k_interpolates8kAndClampsOverflow() {
        val src = FloatArray(80) { if (it == 0) 0f else 65536f }
        val out = FloatArray(160)

        assertEquals(160, resampleTo16k(src, 80, out))
        assertEquals(0f, out[0], 1e-6f)
        assertEquals(1f, out[1], 1e-6f)
        assertEquals(1f, out[159], 1e-6f)
    }

    @Test
    fun sampleWindow_firesOnlyAfterFullWindowThenEveryHop() {
        val window = GrowlSampleWindow()
        val chunk = FloatArray(160)
        var fired = 0
        var appended = 0
        val fireAt = mutableListOf<Int>()
        repeat(200) {
            appended += 160
            if (window.append(chunk, 160)) {
                fired++
                fireAt += appended
            }
        }

        assertEquals(listOf(15680, 23680), fireAt.take(2))
        assertTrue(fired >= 2)
    }

    @Test
    fun sampleWindow_snapshotIsOldestFirst() {
        val window = GrowlSampleWindow()
        val samples = FloatArray(YAMNET_WINDOW_SAMPLES + 100) { it.toFloat() }
        window.append(samples, samples.size)

        val snapshot = window.snapshot()
        assertEquals(100f, snapshot.first())
        assertEquals((YAMNET_WINDOW_SAMPLES + 99).toFloat(), snapshot.last())
        assertContentEquals(samples.copyOfRange(100, samples.size), snapshot)
    }

    @Test
    fun sampleWindow_clearRequiresRefill() {
        val window = GrowlSampleWindow()
        assertTrue(window.append(FloatArray(YAMNET_WINDOW_SAMPLES), YAMNET_WINDOW_SAMPLES))
        window.clear()
        assertFalse(window.append(FloatArray(YAMNET_HOP_SAMPLES), YAMNET_HOP_SAMPLES))
    }

    @Test
    fun requireClassCount_accepts521Scores() {
        requireClassCount(521)
    }

    @Test
    fun requireClassCount_failsModelLoadWhenOutputIsNot521Scores() {
        val error = assertFailsWith<IllegalStateException> { requireClassCount(1024) }
        assertEquals("YAMNet outputs 1024 scores instead of 521", error.message)
        assertFailsWith<IllegalStateException> { requireClassCount(520) }
    }

    @Test
    fun session_dropsResultsFromSessionStoppedAndRestarted() {
        val session = GrowlSession()
        session.begin()
        val staleId = session.id()
        session.end()
        session.begin()

        assertFalse(session.isCurrent(staleId))
        assertTrue(session.isCurrent(session.id()))
    }

    @Test
    fun session_dropsResultsAfterStop() {
        val session = GrowlSession()
        session.begin()
        val id = session.id()
        session.end()

        assertFalse(session.isCurrent(id))
    }
}
