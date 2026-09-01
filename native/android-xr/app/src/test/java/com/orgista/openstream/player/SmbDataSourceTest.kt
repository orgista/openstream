package com.orgista.openstream.player

import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import com.orgista.openstream.data.NasConnection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SmbDataSourceTest {
    private val connection = NasConnection(
        id = "nas-1",
        name = "Home NAS",
        host = "192.168.1.100",
        share = "media",
        username = "admin",
        password = "secretpassword",
    )

    @Test
    fun `isHostAllowed allows matching host on smb scheme`() {
        assertTrue(SmbHostPolicy.isHostAllowed("smb://192.168.1.100/media/movie.mkv", "192.168.1.100"))
        assertTrue(SmbHostPolicy.isHostAllowed("SMB://192.168.1.100/media/movie.mkv", "192.168.1.100"))
        assertTrue(SmbHostPolicy.isHostAllowed("smb://MY-NAS/media/movie.mkv", "my-nas"))
        assertTrue(
            SmbHostPolicy.isHostAllowed(
                "smb://192.168.1.100/media/A Boy Named Charlie Brown (1969)/movie.mkv",
                "192.168.1.100",
            ),
        )
        assertTrue(SmbHostPolicy.isHostAllowed("smb://my-nas/media/Amélie/movie.mkv", "MY-NAS"))
    }

    @Test
    fun `isHostAllowed rejects mismatched host to prevent SMB credential relay`() {
        assertFalse(SmbHostPolicy.isHostAllowed("smb://attacker.evil.com/share/video.mkv", "192.168.1.100"))
        assertFalse(SmbHostPolicy.isHostAllowed("smb://192.168.1.101/share/video.mkv", "192.168.1.100"))
        assertFalse(SmbHostPolicy.isHostAllowed("smb://rogue-nas.local/share/video.mkv", "safe-nas.local"))
    }

    @Test
    fun `isHostAllowed rejects non-SMB schemes`() {
        assertFalse(SmbHostPolicy.isHostAllowed("http://192.168.1.100/share/video.mkv", "192.168.1.100"))
        assertFalse(SmbHostPolicy.isHostAllowed("https://192.168.1.100/share/video.mkv", "192.168.1.100"))
        assertFalse(SmbHostPolicy.isHostAllowed("ftp://192.168.1.100/share/video.mkv", "192.168.1.100"))
        assertFalse(SmbHostPolicy.isHostAllowed("file:///share/video.mkv", "192.168.1.100"))
    }

    @Test
    fun `isHostAllowed rejects empty, null, or malformed URIs`() {
        assertFalse(SmbHostPolicy.isHostAllowed("smb:///share/video.mkv", "192.168.1.100"))
        assertFalse(SmbHostPolicy.isHostAllowed("", "192.168.1.100"))
        assertFalse(SmbHostPolicy.isHostAllowed("not-a-valid-uri", "192.168.1.100"))
    }

    @Test
    fun `factory creates SmbDataSource instance with configured connection`() {
        val factory = SmbDataSource.Factory(connection)
        val created = factory.createDataSource()
        assertTrue(created is SmbDataSource)
    }

    @Test
    fun `closing a transfer that never opened does not notify listeners`() {
        var ended = 0
        val source = SmbDataSource(connection)
        source.addTransferListener(object : TransferListener {
            override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
            override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
            override fun onBytesTransferred(
                source: DataSource,
                dataSpec: DataSpec,
                isNetwork: Boolean,
                bytesTransferred: Int,
            ) = Unit
            override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
                ended++
            }
        })

        source.close()

        assertEquals(0, ended)
    }
}
