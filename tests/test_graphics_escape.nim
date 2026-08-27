## Regression test: drawText must XML-escape special characters.
## Regression test: drawText must XML-escape special characters.
import std/xmlparser
import std/strutils
import ../src/robocode_tankroyale_botapi/graphics

clearGraphics()
drawText("Health: 50 > 25 & <alive>", 10.0, 20.0)
let svg = svgOutput()

# Must contain escaped entities
assert svg.contains("&gt;"),  "missing &gt;"
assert svg.contains("&amp;"), "missing &amp;"
assert svg.contains("&lt;"),  "missing &lt;"

# Must NOT contain raw unescaped tag inside text content.
assert not svg.contains("<alive>"), "raw <alive> must not appear"

# Parse as XML to confirm well-formedness (raises on bad XML).
discard parseXml(svg)

echo "PASS: drawText XML escaping"
