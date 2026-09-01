package com.orgista.openstream.iptv

/**
 * A familiar pay-TV lineup inspired by the current DIRECTV signature tiers.
 * These are organizational labels only; OpenStream is not affiliated with DIRECTV.
 */
enum class LiveChannelPackage(val id: String, val label: String) {
    LOCAL("local", "Local"),
    ENTERTAINMENT("entertainment", "Entertainment"),
    CHOICE("choice", "Choice"),
    KIDS("kids", "Kids & Family"),
    ULTIMATE("ultimate", "Ultimate"),
    PREMIER("premier", "Premier"),
    SPORTS_PACK("sports-pack", "Sports Pack"),
    LEAGUE_SPORTS("league-sports", "League Sports"),
    PPV("ppv", "Pay Per View"),
    OTHER("other", "Other"),
}

data class LiveChannelRail(
    val id: String,
    val title: String,
    val channels: List<IptvChannel>,
)

data class LiveChannelSearchEntry(
    val channel: IptvChannel,
    val normalizedName: String,
    val searchableText: String,
)

object LiveChannelPackagePolicy {
    private const val LOCAL_LIMIT = 16
    private val lineupLimits = mapOf(
        LiveChannelPackage.ENTERTAINMENT to 95,
        LiveChannelPackage.CHOICE to 35,
        LiveChannelPackage.KIDS to 50,
        LiveChannelPackage.ULTIMATE to 35,
        LiveChannelPackage.PREMIER to 40,
        LiveChannelPackage.SPORTS_PACK to 45,
        LiveChannelPackage.LEAGUE_SPORTS to 40,
        LiveChannelPackage.PPV to 30,
    )
    // The DIRECTV guide supplied for this build is the Dallas–Fort Worth
    // market. The complete national local catalog remains available in the
    // manager, while the primary guide starts with this compact local set.
    private val preferredLocalCallSigns = setOf(
        "KDAF", "KDFI", "KDFW", "KERA", "KPXD", "KSTR", "KTVT", "KTXA",
        "KUVN", "KXAS", "KXTX", "WFAA",
    )
    val orderedPackages: List<LiveChannelPackage> = listOf(
        LiveChannelPackage.LOCAL,
        LiveChannelPackage.ENTERTAINMENT,
        LiveChannelPackage.CHOICE,
        LiveChannelPackage.KIDS,
        LiveChannelPackage.ULTIMATE,
        LiveChannelPackage.PREMIER,
        LiveChannelPackage.SPORTS_PACK,
        LiveChannelPackage.LEAGUE_SPORTS,
        LiveChannelPackage.PPV,
    )
    val defaultEnabledPackageIds: Set<String> = linkedSetOf(
        LiveChannelPackage.LOCAL.id,
        LiveChannelPackage.ENTERTAINMENT.id,
        LiveChannelPackage.CHOICE.id,
        LiveChannelPackage.KIDS.id,
        LiveChannelPackage.ULTIMATE.id,
        LiveChannelPackage.PREMIER.id,
        LiveChannelPackage.SPORTS_PACK.id,
        LiveChannelPackage.PPV.id,
    )

    private val ppv = Regex("(?i)\\b(?:ppv|pay[ -]?per[ -]?view|main event|live event|events?)\\b")
    private val local = Regex("(?i)\\b(?:locals?|affiliate|regional)\\b")
    private val kidsGroup = Regex("(?i)^\\s*(?:kids?(?:[ &]+family)?|children|family|preschool|youth)\\s*$")
    private val kidsChannels = Regex(
        "(?i)^(?:pbs kids|babyfirst|kartoon channel|toon ?goggles|nick jr|nickelodeon|nicktoons|" +
            "disney junior|disney channel|disney xd|universal kids|discovery family|cartoon network|boomerang)(?: |$)",
    )
    private val sportsNetworkGroup = Regex("(?i)^\\s*(?:usa[ -]?)?sports networks?\\s*$")
    private val leagueSportsGroups = setOf(
        "nfl", "ncaaf", "mlb", "milb", "nba", "wnba", "nhl / echl", "hockey",
        "futbol", "efl", "mls", "f1 tv", "big10+", "dazn", "espn+", "espn+ (b)",
        "fox one", "peacock sports", "sec+ / acc extra", "sportsnet+", "stan sport",
        "tsn+", "cricket", "tennis tv",
    )
    private val leagueSports = Regex(
        "(?i)\\b(?:nfl|ncaaf|mlb|milb|nba|wnba|nhl|echl|hockey|futbol|soccer|efl|mls|f1|big10|dazn|espn\\+|sec\\+|acc extra|peacock sports|sportsnet\\+|stan sport|tsn\\+|cricket|tennis tv|league pass|extra innings|center ice|redzone)\\b",
    )
    private val sportsPack = Regex(
        "(?i)\\b(?:sports networks?|sports pack|espn|espn2|espnews|espnu|fs1|fs2|cbs sports|golf channel|mlb network|nba tv|nfl network|nhl network|sec network|acc network|big ten network|tennis channel|tudn)\\b",
    )
    private val premierChannels = Regex(
        "(?i)^(?:hbo(?: |$)|cinemax(?: |$)|max(?: |$)|showtime(?: |$)|starz(?: |$)|the movie channel(?: |$)|flx(?: |$)|sho x bet(?: |$)|paramount\\+ with showtime(?: |$))",
    )
    private val ultimateChannels = Regex(
        "(?i)^(?:american heroes|boomerang|cbs sports network|destination america|discovery life|fx movie channel|fxm|fyi|lm n|lmn|logo|magnolia network|nat geo wild|nhl network|science(?: channel)?|smithsonian channel|starz encore|universal kids)(?: |$)",
    )
    private val choiceChannels = Regex(
        "(?i)^(?:acc network|big ten network|cooking channel|discovery family|espnews|espnu|game show network|golf channel|hallmark|history|investigation discovery|mlb network|motortrend|nba tv|nfl network|nick jr|own|oxygen|sec network|tennis channel|travel channel|weather channel)(?: |$)",
    )
    private val entertainmentChannels = Regex(
        "(?i)^(?:a&e|abc|amc|animal planet|bbc america|bet|bravo|cartoon network|cbs|cmt|cnbc|cnn|comedy central|c-span|discovery|disney channel|disney junior|disney xd|e!|espn|espn2|food network|fox|fox business|fox news|freeform|fs1|fx|fxx|hallmark channel|hgtv|hl n|hln|ifc|ion|lifetime|msnbc|mtv|national geographic|nbc|news|newsmax|newsnation|nickelodeon|paramount network|pbs|syfy|tbs|telemundo|tlc|tnt|tru tv|trutv|tv land|unimas|univision|usa network|vh1|we tv)(?: |$)",
    )

    private fun normalizedName(channel: IptvChannel): String = channel.name
        .replace(Regex("(?i)\\([^)]*(?:east|west|sd|hd|fhd|uhd|4k|\\d{3,4}p)[^)]*\\)"), " ")
        .replace(Regex("(?i)\\b(?:east|west|sd|hd|fhd|uhd|4k|\\d{3,4}p)\\b"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()

    fun packageFor(channel: IptvChannel): LiveChannelPackage {
        val searchable = "${channel.group} ${channel.name}"
        val name = normalizedName(channel)
        return when {
            kidsGroup.matches(channel.group) || kidsChannels.containsMatchIn(name) -> LiveChannelPackage.KIDS
            ppv.containsMatchIn(searchable) -> LiveChannelPackage.PPV
            local.containsMatchIn(searchable) -> LiveChannelPackage.LOCAL
            sportsNetworkGroup.matches(channel.group) -> LiveChannelPackage.SPORTS_PACK
            channel.group.trim().lowercase() in leagueSportsGroups -> LiveChannelPackage.LEAGUE_SPORTS
            leagueSports.containsMatchIn(searchable) -> LiveChannelPackage.LEAGUE_SPORTS
            sportsPack.containsMatchIn(searchable) -> LiveChannelPackage.SPORTS_PACK
            premierChannels.containsMatchIn(name) -> LiveChannelPackage.PREMIER
            ultimateChannels.containsMatchIn(name) -> LiveChannelPackage.ULTIMATE
            choiceChannels.containsMatchIn(name) -> LiveChannelPackage.CHOICE
            entertainmentChannels.containsMatchIn(name) -> LiveChannelPackage.ENTERTAINMENT
            else -> LiveChannelPackage.OTHER
        }
    }

    fun channelKey(channel: IptvChannel): String = "${channel.sourceId}:${channel.id}"

    /** Permanent Kids Mode receives only explicitly child-classified channels. */
    fun kidsChannels(channels: List<IptvChannel>): List<IptvChannel> = channels
        .filter { packageFor(it) == LiveChannelPackage.KIDS }
        .distinctBy(::channelKey)

    /** The complete catalog remains searchable even when its package is disabled. */
    fun searchChannels(channels: List<IptvChannel>, query: String, limit: Int = 100): List<IptvChannel> {
        return searchIndexedChannels(buildSearchIndex(channels), query, limit)
    }

    fun buildSearchIndex(channels: List<IptvChannel>): List<LiveChannelSearchEntry> =
        channels.distinctBy(::channelKey).map { channel ->
            val normalizedName = normalizeSearch(channel.name)
            LiveChannelSearchEntry(
                channel = channel,
                normalizedName = normalizedName,
                searchableText = normalizeSearch("${channel.name} ${channel.group} ${packageFor(channel).label}"),
            )
        }

    fun searchIndexedChannels(
        index: List<LiveChannelSearchEntry>,
        query: String,
        limit: Int = 100,
    ): List<IptvChannel> {
        val needle = normalizeSearch(query)
        if (needle.length < 2) return emptyList()
        val tokens = needle.split(' ').filter(String::isNotBlank)
        return index.asSequence()
            .mapNotNull { entry ->
                val score = when {
                    entry.normalizedName == needle -> 0
                    entry.normalizedName.startsWith(needle) -> 1
                    tokens.all { token -> entry.normalizedName.contains(token) } -> 2
                    entry.searchableText.contains(needle) -> 3
                    tokens.all { token -> entry.searchableText.contains(token) } -> 4
                    else -> return@mapNotNull null
                }
                entry.channel to score
            }
            .sortedWith(
                compareBy<Pair<IptvChannel, Int>> { it.second }
                    .thenBy { channelNumberValue(it.first.channelNumber) }
                    .thenBy { it.first.name.lowercase() },
            )
            .map { it.first }
            .take(limit)
            .toList()
    }

    /**
     * The complete catalog remains searchable in Channel Manager, while the
     * guide and main lineup only process enabled packages plus explicit picks.
     */
    fun activeChannels(
        channels: List<IptvChannel>,
        enabledPackageIds: Set<String>,
        favoriteChannelKeys: Set<String>,
    ): List<IptvChannel> = channels.filter { channel ->
        channel.sourceId == ManualLiveChannelPolicy.SOURCE_ID ||
            channelKey(channel) in favoriteChannelKeys ||
            packageFor(channel).id in enabledPackageIds
    }

    /**
     * The provider catalog can contain thousands of city affiliates, league
     * alternates, and quality duplicates. The primary guide intentionally
     * stays close to a conventional pay-TV lineup; the full catalog remains
     * searchable in Channel manager.
     */
    fun lineupChannels(
        channels: List<IptvChannel>,
        enabledPackageIds: Set<String>,
        favoriteChannelKeys: Set<String>,
    ): List<IptvChannel> {
        val active = activeChannels(channels, enabledPackageIds, favoriteChannelKeys)
        val favorites = active.filter { channel ->
            channelKey(channel) in favoriteChannelKeys || channel.sourceId == ManualLiveChannelPolicy.SOURCE_ID
        }
        val sortOrder = compareBy<IptvChannel> { channelNumberValue(it.channelNumber) }
            .thenBy { it.name.lowercase() }
        val packaged = buildList {
            orderedPackages.forEach { packageInfo ->
                if (packageInfo.id !in enabledPackageIds) return@forEach
                val candidates = active.asSequence()
                    .filter { packageFor(it) == packageInfo }
                    .distinctBy(::lineupIdentity)
                    .sortedWith(sortOrder)
                    .toList()
                val selected = if (packageInfo == LiveChannelPackage.LOCAL) {
                    val market = candidates.filter(::matchesPreferredLocalMarket)
                    (if (market.isNotEmpty()) market else candidates).take(LOCAL_LIMIT)
                } else {
                    candidates.take(lineupLimits[packageInfo] ?: 0)
                }
                addAll(selected)
            }
        }
        return (favorites + packaged).distinctBy(::channelKey)
    }

    fun rails(
        channels: List<IptvChannel>,
        enabledPackageIds: Set<String>,
        favoriteChannelKeys: Set<String>,
    ): List<LiveChannelRail> {
        val alphabetic = compareBy<IptvChannel> { it.name.lowercase() }
        val favorites = channels
            .filter { channelKey(it) in favoriteChannelKeys || it.sourceId == ManualLiveChannelPolicy.SOURCE_ID }
            .distinctBy(::channelKey)
            .sortedWith(alphabetic)
        return buildList {
            if (favorites.isNotEmpty()) add(LiveChannelRail("my-channels", "My Channels", favorites))
            orderedPackages.forEach { packageInfo ->
                if (packageInfo.id !in enabledPackageIds) return@forEach
                val packaged = channels.filter { packageFor(it) == packageInfo }.sortedWith(alphabetic)
                if (packaged.isNotEmpty()) add(LiveChannelRail(packageInfo.id, packageInfo.label, packaged))
            }
        }
    }

    private fun matchesPreferredLocalMarket(channel: IptvChannel): Boolean {
        val words = channel.name.uppercase().split(Regex("[^A-Z0-9]+"))
        return words.any { it in preferredLocalCallSigns }
    }

    private fun lineupIdentity(channel: IptvChannel): String = normalizedName(channel)
        .replace(Regex("(?i)^\\s*(?:us|usa)\\s*[:|\\-]\\s*"), "")
        .lowercase()
        .filter(Char::isLetterOrDigit)

    private fun normalizeSearch(value: String): String = value
        .lowercase()
        .replace(Regex("[^a-z0-9]+"), " ")
        .trim()
        .replace(Regex("\\s+"), " ")

    private fun channelNumberValue(value: String): Double = value.toDoubleOrNull() ?: Double.MAX_VALUE
}

object ManualLiveChannelPolicy {
    const val SOURCE_ID = "manual"

    fun isValid(name: String, streamUrl: String): Boolean =
        name.trim().isNotEmpty() && name.trim().length <= 80 && IptvEndpointPolicy.isPlayableStream(streamUrl.trim())
}
