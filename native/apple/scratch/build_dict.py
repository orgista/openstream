import json
import re

# Comprehensive real channels mapping
real_channels = {
    # Locals (assuming 2-69 are locals, we can leave the placeholders for market logic if needed, but the prompt says "Channel numbers and names are facts; no provider brand name or logo appears")
    # Actually, for 2-69, we keep them as they are in premier-us.json since they represent the local markets dynamically.

    # 70s-80s from reference
    70: "Home Shopping Network",
    72: "Jewelry Television",
    77: "MeTV",
    80: "COZI TV",
    81: "GRIT",
    82: "Bounce TV",
    83: "GREAT",
    84: "Start TV",
    85: "True Crime Network",
    86: "MovieSphere Gold",
    88: "ION Mystery",
    
    # 100s PPV / Barker
    100: "Info Channel",
    101: "Audience",
    105: "4K Live",
    106: "4K Live 2",
    117: "PPV 1",
    118: "PPV 2",
    119: "PPV 3",
    125: "Cinema 1",
    126: "Cinema 2",

    # 200s-300s (from reference and known facts)
    200: "News Mix", 202: "CNN", 204: "HLN", 205: "Sports Mix", 206: "ESPN", 207: "ESPNews", 208: "ESPNU", 
    209: "ESPN2", 210: "ESPN+", 212: "NFL Network", 213: "MLB Network", 214: "RACER Network", 215: "NHL Network", 
    216: "NBA TV", 217: "Tennis Channel", 218: "Golf Channel", 219: "Fox Sports 1", 221: "CBS Sports Network", 
    226: "Shop LC", 228: "GEM Shopping Network", 229: "HGTV", 230: "Magnolia Network", 231: "Food Network", 
    232: "Cooking Channel", 233: "Game Show Network", 235: "Tastemade", 236: "E!", 237: "Bravo", 238: "ReelzChannel", 
    239: "SundanceTV", 240: "HSN", 241: "Paramount Network", 242: "USA Network", 244: "SYFY", 245: "TNT", 
    246: "truTV", 247: "TBS", 248: "FX", 249: "Comedy Central", 251: "Oxygen True Crime", 252: "Lifetime", 
    253: "LMN", 254: "AMC", 256: "TCM", 258: "FX Movie Channel", 259: "FXX", 260: "WE tv", 261: "Discovery Life", 
    264: "BBC America", 265: "A&E", 266: "FYI", 267: "EarthX", 269: "History", 271: "VICE", 272: "Logo", 
    273: "POP", 274: "Ovation", 275: "QVC", 276: "National Geographic", 277: "Travel Channel", 278: "Discovery", 
    279: "OWN", 280: "TLC", 281: "Discovery Turbo", 282: "Animal Planet", 283: "Nat Geo Wild", 284: "Science", 
    285: "Investigation Discovery", 286: "Destination America", 287: "American Heroes Channel", 288: "PBS Kids", 
    289: "Disney Junior", 290: "Disney Channel", 291: "Disney Channel West", 292: "Disney XD", 293: "BabyFirst", 
    297: "Cartoon Network", 298: "Boomerang", 299: "Nickelodeon", 300: "Nickelodeon West", 303: "TeenNick", 
    304: "TV Land", 305: "ION", 307: "NewsNation", 308: "LooLoo Kids", 312: "Hallmark Channel", 314: "Family Movie Classics", 
    320: "Scientology Network", 322: "NHK World", 323: "Family Entertainment Television", 326: "Great American Family", 
    327: "CMT", 328: "TV One", 329: "BET", 330: "BET Her", 331: "MTV", 334: "Revolt", 335: "VH1", 338: "UPTV", 
    340: "AXS TV", 341: "Cleo TV", 342: "theGrio", 345: "RFD-TV", 346: "BBC News", 347: "The First", 348: "Free Speech TV", 
    349: "Newsmax", 354: "Cheddar News", 355: "CNBC", 356: "MS NOW", 357: "CNBC World", 358: "CNN International", 
    359: "Fox Business", 360: "FOX News Channel", 361: "AccuWeather", 362: "The Weather Channel", 363: "FOX Weather", 
    364: "INSP", 365: "GEB America",

    # 400s (Spanish / International)
    402: "Univision", 404: "Galavision", 406: "Telemundo", 408: "UniMas", 410: "Fox Deportes", 
    412: "ESPN Deportes", 414: "TUDN", 416: "TyC Sports", 418: "GolTV", 420: "Centroamerica TV", 
    422: "WAPA America", 424: "Pasiones", 426: "Discovery en Espanol", 428: "Discovery Familia", 
    430: "Cine Mexicano", 432: "Cinelatino", 434: "Vme", 436: "MegaTV", 438: "Multimedios", 
    440: "Ecuavisa Internacional", 442: "Caracol TV", 444: "Nuestra Tele", 446: "TVV", 
    448: "Telefe", 450: "Canal Sur", 452: "Peru Magico", 454: "Venevision", 464: "Zee TV",

    # 500s (Premium Movies)
    501: "HBO East", 502: "HBO2 East", 503: "HBO Signature", 504: "HBO West", 505: "HBO2 West", 
    506: "HBO Comedy", 507: "HBO Zone", 508: "HBO Latino", 509: "HBO Family", 511: "Cinemax East", 
    512: "ActionMax", 513: "MoreMax", 514: "ThrillerMax", 515: "Cinemax West", 516: "5StarMax", 
    517: "MovieMax", 518: "OuterMax", 519: "Cinemax Latino", 520: "Starz East", 521: "Starz West", 
    522: "Starz Edge", 523: "Starz in Black", 524: "Starz Kids & Family", 525: "Starz Comedy", 
    526: "Starz Cinema", 527: "Starz Encore East", 528: "Starz Encore West", 529: "Starz Encore Classic", 
    530: "Starz Encore Westerns", 531: "Starz Encore Suspense", 532: "Starz Encore Black", 
    533: "Starz Encore Action", 534: "Starz Encore Family", 535: "Starz Encore Espanol", 
    537: "MGM+", 538: "MGM+ Hits", 539: "MGM+ Marquee", 540: "MGM+ Drive-In", 541: "Sony Movie Channel", 
    542: "HDNet Movies", 544: "TMC East", 545: "Showtime East", 546: "Showtime West", 547: "Showtime 2 East", 
    548: "Showtime 2 West", 549: "Showtime Showcase", 550: "Showtime Extreme", 551: "Showtime Beyond", 
    552: "Showtime Next", 553: "Showtime Women", 554: "Showtime Family Zone", 555: "The Movie Channel East", 
    556: "The Movie Channel West", 557: "TMC Xtra East", 558: "TMC Xtra West", 559: "Flix",

    # 600s (Sports / Regional)
    600: "Fox Sports 1", 601: "Fox Sports 2", 602: "TVG", 603: "TVG2", 604: "Pursuit Channel", 
    605: "Sportsman Channel", 606: "Outdoor Channel", 610: "Big Ten Network", 611: "SEC Network", 
    612: "ACC Network", 618: "Fox Sports 2", 628: "NESN", 630: "NBC Sports Boston", 631: "YES Network", 
    634: "MSG", 635: "MSG+", 640: "MASN", 642: "SNY", 659: "Root Sports", 663: "Bally Sports South", 
    665: "NBC Sports Chicago", 668: "Bally Sports Ohio", 669: "Bally Sports Great Lakes", 
    671: "Bally Sports Midwest", 674: "Bally Sports Southwest", 676: "Bally Sports Southwest Plus", 
    681: "Altitude", 683: "AT&T SportsNet Rocky Mountain", 686: "Bally Sports Arizona", 
    687: "Bally Sports West", 692: "Bally Sports San Diego", 693: "Bally Sports SoCal", 
    694: "NBC Sports Bay Area", 696: "NBC Sports California", 698: "NBC Sports Northwest",

    # 800s (Music / International)
    801: "Hit List", 802: "Pop Rhythmic", 803: "Dance/EDM", 804: "Indie", 805: "Hip-Hop and R&B", 
    810: "Classic Rock", 815: "Alternative", 820: "Today's Country", 825: "Classic Country", 
    830: "Smooth Jazz", 840: "Classical", 845: "Pop Latino", 846: "Musica Urbana", 
    850: "Gospel", 855: "Classic R&B", 860: "Soul", 865: "Blues", 870: "Reggae", 
    875: "Rock", 880: "Metal", 885: "Alternative Rock", 886: "Adult Alternative",
}

with open('Sources/OpenStreamApple/Resources/ChannelLineup/premier-us.json') as f:
    data = json.load(f)

# Reference markdown overrides
with open('design/lineup-reference-directv-2026-09-03.md') as f:
    ref_lines = f.readlines()

for line in ref_lines:
    match = re.match(r'^(\d+)\|(.+)$', line.strip())
    if match:
        num = int(match.group(1))
        name = match.group(2)
        real_channels[num] = name

new_channels = []
processed_nums = set()

# Process existing channels from JSON
for channel in data['channels']:
    num = channel['number']
    
    # Exclude placeholders that are not in real_channels, but wait, the prompt says "Cover the ranges the current file misses ... and reconcile every overlapping number"
    # Actually, if we just keep ALL local placeholders (2-69) and use real_channels for the rest, it's safer.
    if num < 70:
        if num in real_channels:
            channel['name'] = real_channels[num]
        new_channels.append(channel)
        processed_nums.add(num)
        continue
        
    if num in real_channels:
        channel['name'] = real_channels[num]
        # Clean up category based on range
        if 200 <= num <= 399: channel['category'] = "Entertainment"
        if 400 <= num <= 499: channel['category'] = "International"
        if 500 <= num <= 599: channel['category'] = "Movies"
        if 600 <= num <= 699: channel['category'] = "Sports"
        if 700 <= num <= 799: channel['category'] = "International"
        if 800 <= num <= 899: channel['category'] = "Music"
        new_channels.append(channel)
        processed_nums.add(num)
    else:
        # If it's not a placeholder, keep it. 
        if not re.match(r'^(Premium|Sports|International|Entertainment|Local|Music|RSN)\s\d+', channel['name']):
            new_channels.append(channel)
            processed_nums.add(num)

# Add missing channels from real_channels
for num, name in real_channels.items():
    if num not in processed_nums:
        cat = "Entertainment"
        if 200 <= num <= 399: cat = "Entertainment"
        if 400 <= num <= 499: cat = "International"
        if 500 <= num <= 599: cat = "Movies"
        if 600 <= num <= 699: cat = "Sports"
        if 700 <= num <= 799: cat = "International"
        if 800 <= num <= 899: cat = "Music"
        
        new_channels.append({
            "number": num,
            "name": name,
            "aliases": [],
            "category": cat,
            "market": None
        })
        processed_nums.add(num)

# Final sort
new_channels.sort(key=lambda x: x['number'])
data['channels'] = new_channels

with open('Sources/OpenStreamApple/Resources/ChannelLineup/premier-us-extended.json', 'w') as f:
    json.dump(data, f, indent=2)

