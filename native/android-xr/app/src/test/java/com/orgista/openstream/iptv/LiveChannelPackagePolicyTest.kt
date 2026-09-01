package com.orgista.openstream.iptv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveChannelPackagePolicyTest {
    private fun channel(id: String, name: String, group: String, sourceId: String = "provider") = IptvChannel(
        id = id,
        sourceId = sourceId,
        sourceName = "Live TV",
        name = name,
        group = group,
        logoUrl = "",
        streamUrl = "https://tv.example.com/$id.m3u8",
    )

    @Test
    fun `provider groups become a direct tv style lineup`() {
        assertEquals(LiveChannelPackage.LOCAL, LiveChannelPackagePolicy.packageFor(channel("1", "WABC 7", "US Local")))
        assertEquals(LiveChannelPackage.PPV, LiveChannelPackagePolicy.packageFor(channel("2", "Main Event 4", "Pay Per View")))
        assertEquals(LiveChannelPackage.SPORTS_PACK, LiveChannelPackagePolicy.packageFor(channel("3", "ESPN", "Sports Networks")))
        assertEquals(LiveChannelPackage.ENTERTAINMENT, LiveChannelPackagePolicy.packageFor(channel("4", "CNN", "24/7 News")))
        assertEquals(LiveChannelPackage.ENTERTAINMENT, LiveChannelPackagePolicy.packageFor(channel("5", "CNN", "Network TV")))
        assertEquals(LiveChannelPackage.ENTERTAINMENT, LiveChannelPackagePolicy.packageFor(channel("6", "ABC (East)", "Network TV")))
        assertEquals(LiveChannelPackage.PREMIER, LiveChannelPackagePolicy.packageFor(channel("7", "HBO East", "Premium Movie Channels")))
        assertEquals(LiveChannelPackage.ULTIMATE, LiveChannelPackagePolicy.packageFor(channel("8", "FX Movie Channel", "Movies")))
        assertEquals(LiveChannelPackage.KIDS, LiveChannelPackagePolicy.packageFor(channel("9", "Discovery Family", "Kids")))
        assertEquals(LiveChannelPackage.LEAGUE_SPORTS, LiveChannelPackagePolicy.packageFor(channel("10", "MLB 01", "MLB Extra Innings")))
        assertEquals(LiveChannelPackage.LEAGUE_SPORTS, LiveChannelPackagePolicy.packageFor(channel("11", "ESPN+ 101", "ESPN+")))
    }

    @Test
    fun `manager exposes only signature style packages plus local sports and ppv`() {
        assertEquals(
            listOf("Local", "Entertainment", "Choice", "Kids & Family", "Ultimate", "Premier", "Sports Pack", "League Sports", "Pay Per View"),
            LiveChannelPackagePolicy.orderedPackages.map { it.label },
        )
        assertEquals(
            setOf(
                LiveChannelPackage.LOCAL.id,
                LiveChannelPackage.ENTERTAINMENT.id,
                LiveChannelPackage.CHOICE.id,
                LiveChannelPackage.KIDS.id,
                LiveChannelPackage.ULTIMATE.id,
                LiveChannelPackage.PREMIER.id,
                LiveChannelPackage.SPORTS_PACK.id,
                LiveChannelPackage.PPV.id,
            ),
            LiveChannelPackagePolicy.defaultEnabledPackageIds,
        )
        assertFalse(LiveChannelPackage.LEAGUE_SPORTS.id in LiveChannelPackagePolicy.defaultEnabledPackageIds)
        assertFalse(LiveChannelPackage.OTHER in LiveChannelPackagePolicy.orderedPackages)
    }

    @Test
    fun `kids lineup includes only channels classified for children`() {
        val pbsKids = channel("pbs-kids", "PBS Kids", "Kids")
        val babyFirst = channel("baby-first", "BabyFirst", "Children")
        val cnn = channel("cnn", "CNN", "Network TV")
        val manualAdult = channel("manual-adult", "Horror Movies", "premier", sourceId = ManualLiveChannelPolicy.SOURCE_ID)

        assertEquals(LiveChannelPackage.KIDS, LiveChannelPackagePolicy.packageFor(pbsKids))
        assertEquals(LiveChannelPackage.KIDS, LiveChannelPackagePolicy.packageFor(babyFirst))
        assertEquals(listOf(pbsKids, babyFirst), LiveChannelPackagePolicy.kidsChannels(listOf(pbsKids, cnn, babyFirst, manualAdult)))
    }

    @Test
    fun `rails use package order and put my channels first`() {
        val channels = listOf(
            channel("news", "News", "News"),
            channel("sport", "ESPN", "Sports Networks"),
            channel("local", "Local 5", "Local"),
            channel("ppv", "Event 1", "PPV"),
        )
        val rails = LiveChannelPackagePolicy.rails(
            channels = channels,
            enabledPackageIds = setOf(
                LiveChannelPackage.LOCAL.id,
                LiveChannelPackage.PPV.id,
                LiveChannelPackage.SPORTS_PACK.id,
                LiveChannelPackage.ENTERTAINMENT.id,
            ),
            favoriteChannelKeys = setOf(LiveChannelPackagePolicy.channelKey(channels.last())),
        )

        assertEquals(listOf("My Channels", "Local", "Entertainment", "Sports Pack", "Pay Per View"), rails.map { it.title })
        assertEquals("Event 1", rails.first().channels.single().name)
    }

    @Test
    fun `disabled packages are hidden without deleting channels`() {
        val sports = channel("sport", "ESPN", "Sports Networks")
        val rails = LiveChannelPackagePolicy.rails(
            channels = listOf(sports),
            enabledPackageIds = setOf(LiveChannelPackage.LOCAL.id),
            favoriteChannelKeys = emptySet(),
        )

        assertTrue(rails.isEmpty())
        assertFalse(LiveChannelPackagePolicy.defaultEnabledPackageIds.isEmpty())
    }

    @Test
    fun `active lineup retains favorites and manual channels outside enabled packages`() {
        val news = channel("news", "CNN", "News")
        val sports = channel("sport", "ESPN", "Sports Networks")
        val manual = channel("manual", "Neighborhood TV", "other", sourceId = ManualLiveChannelPolicy.SOURCE_ID)

        val active = LiveChannelPackagePolicy.activeChannels(
            channels = listOf(news, sports, manual),
            enabledPackageIds = setOf(LiveChannelPackage.ENTERTAINMENT.id),
            favoriteChannelKeys = setOf(LiveChannelPackagePolicy.channelKey(sports)),
        )

        assertEquals(listOf(news, sports, manual), active)
    }

    @Test
    fun `channel manager search finds disabled channels that can be added to my channels`() {
        val cnn = channel("cnn", "CNN", "Network TV")
        val league = channel("mlb", "MLB Extra Innings 01", "MLB Extra Innings")

        val results = LiveChannelPackagePolicy.searchChannels(listOf(cnn, league), "extra innings")

        assertEquals(listOf(league), results)
        assertEquals(
            listOf(league),
            LiveChannelPackagePolicy.activeChannels(
                channels = listOf(cnn, league),
                enabledPackageIds = emptySet(),
                favoriteChannelKeys = setOf(LiveChannelPackagePolicy.channelKey(league)),
            ),
        )
    }

    @Test
    fun `manual channel requires a name and playable web stream`() {
        assertTrue(ManualLiveChannelPolicy.isValid("My station", "https://tv.example.com/live.m3u8"))
        assertFalse(ManualLiveChannelPolicy.isValid("", "https://tv.example.com/live.m3u8"))
        assertFalse(ManualLiveChannelPolicy.isValid("My station", "file:///sdcard/live.m3u8"))
    }

    @Test
    fun `provider category lineup stays bounded while full catalog remains searchable`() {
        val sample = listOf(
            channel("abc", "ABC (East)", "Network TV"),
            channel("espn", "ESPN", "Sports Networks"),
            channel("local", "ABC (KABC) Los Angeles", "Locals"),
            channel("event", "EVENTS 01", "Events"),
            channel("league", "ESPN+ 101", "ESPN+"),
            channel("music", "Classic Rock", "Music"),
            channel("international", "BBC UK", "UK"),
        )

        val active = LiveChannelPackagePolicy.activeChannels(
            channels = sample,
            enabledPackageIds = LiveChannelPackagePolicy.defaultEnabledPackageIds,
            favoriteChannelKeys = emptySet(),
        )

        assertEquals(listOf("abc", "espn", "local", "event"), active.map { it.id })
        assertEquals("music", LiveChannelPackagePolicy.searchChannels(sample, "classic rock").single().id)
    }

    @Test
    fun `main guide is bounded and keeps supplied direct tv market locals`() {
        val locals = (1..60).map { index ->
            channel("local-$index", "ABC Local $index", "Locals")
        } + listOf(
            channel("wfaa", "ABC (WFAA) Dallas, TX", "Locals"),
            channel("kxas", "NBC (KXAS) Dallas, TX", "Locals"),
        )
        val entertainment = (1..180).map { index ->
            channel("ent-$index", "CNN ${index.toString().padStart(3, '0')}", "Network TV")
        }

        val lineup = LiveChannelPackagePolicy.lineupChannels(
            channels = locals + entertainment,
            enabledPackageIds = setOf(
                LiveChannelPackage.LOCAL.id,
                LiveChannelPackage.ENTERTAINMENT.id,
            ),
            favoriteChannelKeys = emptySet(),
        )

        assertTrue(lineup.any { it.id == "wfaa" })
        assertTrue(lineup.any { it.id == "kxas" })
        assertTrue(lineup.count { LiveChannelPackagePolicy.packageFor(it) == LiveChannelPackage.LOCAL } <= 16)
        assertTrue(lineup.count { LiveChannelPackagePolicy.packageFor(it) == LiveChannelPackage.ENTERTAINMENT } <= 95)
    }

    @Test
    fun `main guide collapses quality variants even for short channel names`() {
        val lineup = LiveChannelPackagePolicy.lineupChannels(
            channels = listOf(
                channel("ae", "A&E", "Network TV"),
                channel("ae-720", "A&E (720p)", "Network TV"),
            ),
            enabledPackageIds = setOf(LiveChannelPackage.ENTERTAINMENT.id),
            favoriteChannelKeys = emptySet(),
        )

        assertEquals(1, lineup.size)
    }

    @Test
    fun `indexed search ranks channel names ahead of schedule text`() {
        val comedy = channel("comedy", "Comedy Central HD", "Network TV")
        val gma = channel("gma", "GMA3", "Network TV")
        val programs = listOf(
            IptvGuideProgram(
                channelKey = LiveChannelPackagePolicy.channelKey(gma),
                title = "Comedy Central Presents",
                startMillis = 1L,
                endMillis = 2L,
            ),
        )

        val index = LiveGuideSearchIndex.build(listOf(gma, comedy), programs)

        assertEquals("comedy", LiveGuideSearchIndex.search(index, "comedy central").first().id)
    }

    @Test
    fun `channel manager index finds exact channel quickly`() {
        val channels = (1..5_000).map { index ->
            channel("channel-$index", "Station $index", "Other")
        } + channel("comedy", "Comedy Central", "Network TV")

        val index = LiveChannelPackagePolicy.buildSearchIndex(channels)

        assertEquals("comedy", LiveChannelPackagePolicy.searchIndexedChannels(index, "comedy central").first().id)
    }

    @Test
    fun `full catalog search finds a channel omitted from the capped guide`() {
        val catalog = (1..100).map { index ->
            channel("ent-$index", "AMC Station $index", "Network TV")
        } + channel("comedy", "Comedy Central (1080p)", "Comedy")
        val lineup = LiveChannelPackagePolicy.lineupChannels(
            channels = catalog,
            enabledPackageIds = setOf(LiveChannelPackage.ENTERTAINMENT.id),
            favoriteChannelKeys = emptySet(),
        )

        assertFalse(lineup.any { it.id == "comedy" })
        assertEquals(
            "comedy",
            LiveChannelPackagePolicy.searchIndexedChannels(
                LiveChannelPackagePolicy.buildSearchIndex(catalog),
                "comedy central",
            ).first().id,
        )
    }
}
