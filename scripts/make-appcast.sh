#!/usr/bin/env bash
# Writes a Sparkle appcast for one release to stdout.
#   scripts/make-appcast.sh <version> <archive.zip> <download-url> <private-key-file>
# SPARKLE_BIN points at Sparkle's bin/ (sign_update). Release notes come from CHANGELOG.md's "## <version>" section.
set -euo pipefail
VERSION="$1"; ZIP="$2"; URL="$3"; KEY="$4"
SIGN="${SPARKLE_BIN:?set SPARKLE_BIN to the Sparkle bin directory}/sign_update"
cd "$(dirname "$0")/.."

# sign_update prints: sparkle:edSignature="…" length="…"
ATTRS="$("$SIGN" --ed-key-file "$KEY" "$ZIP")"
case "$ATTRS" in *edSignature*) ;; *) echo "sign_update failed: $ATTRS" >&2; exit 1 ;; esac

# A function, not an inline $(…): bash 3.2 misparses parentheses inside quoted awk programs there.
notes() {
  awk -v v="## $VERSION" '$0 == v {on=1; next} /^## / && on {exit} on' CHANGELOG.md 2>/dev/null \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
    | awk 'BEGIN{print "<ul>"} /^- /{sub(/^- /,""); print "<li>" $0 "</li>"} END{print "</ul>"}'
}
NOTES="$(notes)"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>AgentSweep</title>
    <link>https://github.com/ai-suifeng/agent-clean-mac</link>
    <language>zh-CN</language>
    <item>
      <title>AgentSweep $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<h3>AgentSweep $VERSION</h3>$NOTES]]></description>
      <enclosure url="$URL" type="application/octet-stream" $ATTRS />
    </item>
  </channel>
</rss>
XML
