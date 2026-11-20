#!/usr/bin/env python3
"""Checks Sparkle's feed after make dist, for scripts/release.sh: one new item, of the version,
with the download URL and the disk image's size, signed; the earlier items as they were. It prints
the item's EdDSA signature, for sign_update; its findings go to standard error.

    check_feed.py <feed> <earlier feed, or an empty file> <version> <download URL> <size>
"""
import sys
import xml.etree.ElementTree as ET

feed, earlier, version, url, size = sys.argv[1:]
S = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
problems = []


def items(path):
    try:
        return ET.parse(path).getroot().findall("channel/item")
    except ET.ParseError as error:
        if path == feed:
            sys.exit(f"The feed is not well-formed XML: {error}")
        return []  # no feed before the first release


def key(item):
    enclosure = item.find("enclosure")
    return (item.findtext(S + "version"), enclosure.get("url") if enclosure is not None else None,
            enclosure.get(S + "edSignature") if enclosure is not None else None)


new, old = items(feed), items(earlier)
if [key(i) for i in new if i.findtext(S + "version") != version] != [key(i) for i in old]:
    problems.append("the earlier items changed")
mine = [i for i in new if i.findtext(S + "version") == version]
if len(mine) != 1:
    problems.append(f"{len(mine)} items for {version}, not one")
else:
    item = mine[0]
    enclosure = item.find("enclosure")
    if item.findtext(S + "shortVersionString") != version:
        problems.append(f"shortVersionString is {item.findtext(S + 'shortVersionString')}")
    if enclosure is None:
        problems.append("no enclosure")
    else:
        if enclosure.get("url") != url:
            problems.append(f"the download URL is {enclosure.get('url')}")
        if enclosure.get("length") != size:
            problems.append(f"the length is {enclosure.get('length')}, the disk image's size {size}")
        if not enclosure.get(S + "edSignature"):
            problems.append("the enclosure has no sparkle:edSignature")
    minimum = item.findtext(S + "minimumSystemVersion")
    if minimum and not minimum.startswith("15"):
        problems.append(f"the minimum macOS is {minimum}, not 15")
    if not (item.findtext("description") or "").strip():
        problems.append("no release notes")
if problems:
    sys.exit("The feed's item for " + version + ": " + "; ".join(problems) + ".")
print(f"One new item for {version}, {len(old)} earlier ones unchanged.", file=sys.stderr)
print(mine[0].find("enclosure").get(S + "edSignature"))
