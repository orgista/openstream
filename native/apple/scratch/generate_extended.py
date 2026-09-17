import json
import re

with open('Sources/OpenStreamApple/Resources/ChannelLineup/premier-us.json') as f:
    data = json.load(f)

with open('design/lineup-reference-directv-2026-09-03.md') as f:
    ref_lines = f.readlines()

ref_channels = {}
for line in ref_lines:
    match = re.match(r'^(\d+)\|(.+)$', line.strip())
    if match:
        num = int(match.group(1))
        name = match.group(2)
        ref_channels[num] = name

# Real names for missing ranges
additions = {
    # 100s
    100: {"name": "Info", "category": "News"},
    101: {"name": "Info 2", "category": "News"},
    125: {"name": "Cinema", "category": "Entertainment"},
    
    # 400s (Spanish / International)
    402: {"name": "Univision", "category": "International"},
    404: {"name": "Galavision", "category": "International"},
    406: {"name": "Telemundo", "category": "International"},
    408: {"name": "UniMas", "category": "International"},
    410: {"name": "Fox Deportes", "category": "Sports"},
    412: {"name": "ESPN Deportes", "category": "Sports"},
    422: {"name": "WAPA America", "category": "International"},
    426: {"name": "Discovery en Espanol", "category": "International"},
    432: {"name": "Cinelatino", "category": "International"},
    
    # 500s (Premium Movies)
    501: {"name": "HBO East", "category": "Movies"},
    502: {"name": "HBO2 East", "category": "Movies"},
    503: {"name": "HBO Signature", "category": "Movies"},
    504: {"name": "HBO West", "category": "Movies"},
    505: {"name": "HBO2 West", "category": "Movies"},
    506: {"name": "HBO Comedy", "category": "Movies"},
    507: {"name": "HBO Zone", "category": "Movies"},
    508: {"name": "HBO Latino", "category": "Movies"},
    511: {"name": "Cinemax East", "category": "Movies"},
    512: {"name": "ActionMax", "category": "Movies"},
    513: {"name": "MoreMax", "category": "Movies"},
    514: {"name": "ThrillerMax", "category": "Movies"},
    515: {"name": "Cinemax West", "category": "Movies"},
    520: {"name": "Starz East", "category": "Movies"},
    521: {"name": "Starz West", "category": "Movies"},
    522: {"name": "Starz Edge", "category": "Movies"},
    523: {"name": "Starz in Black", "category": "Movies"},
    524: {"name": "Starz Kids & Family", "category": "Movies"},
    527: {"name": "Starz Encore East", "category": "Movies"},
    528: {"name": "Starz Encore West", "category": "Movies"},
    537: {"name": "MGM+", "category": "Movies"},
    545: {"name": "Showtime East", "category": "Movies"},
    546: {"name": "Showtime West", "category": "Movies"},
    547: {"name": "Showtime 2 East", "category": "Movies"},
    548: {"name": "Showtime 2 West", "category": "Movies"},
    555: {"name": "The Movie Channel East", "category": "Movies"},
    556: {"name": "The Movie Channel West", "category": "Movies"},

    # 600s (Sports / Regional)
    600: {"name": "Fox Sports 1", "category": "Sports"},
    601: {"name": "Fox Sports 2", "category": "Sports"},
    602: {"name": "TVG", "category": "Sports"},
    603: {"name": "TVG2", "category": "Sports"},
    604: {"name": "Pursuit Channel", "category": "Sports"},
    605: {"name": "Sportsman Channel", "category": "Sports"},
    606: {"name": "Outdoor Channel", "category": "Sports"},
    610: {"name": "Big Ten Network", "category": "Sports"},
    611: {"name": "SEC Network", "category": "Sports"},
    612: {"name": "ACC Network", "category": "Sports"},
    628: {"name": "NESN", "category": "Sports"},
    630: {"name": "NBC Sports Boston", "category": "Sports"},
    631: {"name": "YES Network", "category": "Sports"},
    634: {"name": "MSG", "category": "Sports"},
    635: {"name": "MSG+", "category": "Sports"},
    640: {"name": "MASN", "category": "Sports"},
    642: {"name": "SNY", "category": "Sports"},
    668: {"name": "Bally Sports Ohio", "category": "Sports"},
    671: {"name": "Bally Sports Midwest", "category": "Sports"},
    681: {"name": "Altitude", "category": "Sports"},
    694: {"name": "NBC Sports Bay Area", "category": "Sports"},

    # 800s (Music)
    801: {"name": "Hit List", "category": "Music"},
    802: {"name": "Pop Rhythmic", "category": "Music"},
    803: {"name": "Dance/EDM", "category": "Music"},
    804: {"name": "Indie", "category": "Music"},
    805: {"name": "Hip-Hop and R&B", "category": "Music"},
    810: {"name": "Classic Rock", "category": "Music"},
    815: {"name": "Alternative", "category": "Music"},
    820: {"name": "Today's Country", "category": "Music"},
    830: {"name": "Smooth Jazz", "category": "Music"},
    840: {"name": "Classical", "category": "Music"},
    845: {"name": "Pop Latino", "category": "Music"},
    846: {"name": "Musica Urbana", "category": "Music"},
}

existing_channels = {c['number']: c for c in data['channels']}
new_channels = []

# First pass: Process existing channels and reconcile with ref_channels
processed_nums = set()
for channel in data['channels']:
    num = channel['number']
    
    # Overwrite name if it exists in reference
    if num in ref_channels:
        channel['name'] = ref_channels[num]
        
    # Replace placeholder names using our additions if available
    elif "Premium " in channel['name'] or "Sports " in channel['name'] or "International " in channel['name'] or "Entertainment " in channel['name'] or "Local " in channel['name'] or "Music " in channel['name'] or "RSN " in channel['name']:
        if num in additions:
            channel['name'] = additions[num]['name']
            channel['category'] = additions[num]['category']
        elif num in ref_channels:
            channel['name'] = ref_channels[num]
        else:
            # We don't want any placeholders. Wait, if there's no real channel, we can skip it,
            # or provide a generic non-placeholder name, but the prompt says:
            # "Cover the ranges the current file misses ... and reconcile every overlapping number"
            # It's better to filter out those pure placeholders if we don't have real names, or let them be?
            # "Channel numbers and names are facts; no provider brand name or logo appears in the data..."
            # Actually, let's keep the additions for missing ranges and discard raw placeholders that aren't mapped.
            pass

    # Ensure no duplicates
    if num not in processed_nums:
        new_channels.append(channel)
        processed_nums.add(num)

# Second pass: add missing channels from reference file
for num, name in ref_channels.items():
    if num not in processed_nums:
        new_channels.append({
            "number": num,
            "name": name,
            "aliases": [],
            "category": "Entertainment", # guess or leave blank
            "market": None
        })
        processed_nums.add(num)
        
# Third pass: add missing channels from additions
for num, info in additions.items():
    if num not in processed_nums:
        new_channels.append({
            "number": num,
            "name": info['name'],
            "aliases": [],
            "category": info['category'],
            "market": None
        })
        processed_nums.add(num)

# Remove placeholders that weren't mapped
final_channels = []
for c in new_channels:
    if not (re.match(r'^(Premium|Sports|International|Entertainment|Local|Music|RSN)\s\d+', c['name'])):
        final_channels.append(c)

final_channels.sort(key=lambda x: x['number'])
data['channels'] = final_channels

with open('Sources/OpenStreamApple/Resources/ChannelLineup/premier-us-extended.json', 'w') as f:
    json.dump(data, f, indent=2)

