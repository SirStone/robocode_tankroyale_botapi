## TR-API-GFX — Tier 1 graphics tests.
## Covers: GFX-001 Color RGBA construction/constants, GFX-002 alpha in SVG,
##          GFX-003 text escaping, GFX-004 deterministic SVG output.

import std/unittest
import std/xmlparser
import std/strutils
import ../../src/robocode_tankroyale_botapi/color
import ../../src/robocode_tankroyale_botapi/graphics

# ---------------------------------------------------------------------------
# GFX-001: Color RGBA construction and named constants
# ---------------------------------------------------------------------------

suite "GFX-001 Color RGBA construction":
  test "fromRgb packs RGB with alpha=0xFF":
    let c = fromRgb(255, 0, 128)
    check c.r == 255
    check c.g == 0
    check c.b == 128
    check c.a == 0xFF

  test "fromRgba packs all four channels":
    let c = fromRgba(10, 20, 30, 128)
    check c.r == 10
    check c.g == 20
    check c.b == 30
    check c.a == 128

  test "fromHex '#RRGGBB' implies alpha 255":
    let c = color.fromHex("#FF8000")
    check c.r == 0xFF
    check c.g == 0x80
    check c.b == 0x00
    check c.a == 0xFF

  test "fromHex '#RRGGBBAA' explicit alpha":
    let c = color.fromHex("#FF800040")
    check c.r == 0xFF
    check c.g == 0x80
    check c.b == 0x00
    check c.a == 0x40

  test "toHex omits alpha when 0xFF":
    check fromRgb(255, 128, 0).toHex == "#FF8000"

  test "toHex includes alpha when < 0xFF":
    check fromRgba(255, 128, 0, 64).toHex == "#FF800040"

  test "equality":
    check fromRgb(0, 0, 0) == BLACK
    check fromRgb(255, 255, 255) == WHITE
    check fromRgb(255, 0, 0) == RED
    check fromRgb(0, 255, 0) == LIME
    check fromRgb(0, 0, 255) == BLUE

  test "TRANSPARENT constant has alpha 0":
    check TRANSPARENT.a == 0

  test "round-trip fromHex/toHex":
    # alpha=0xFF: toHex omits AA suffix, so canonical form is 6-digit
    check color.fromHex("#AABBCC").toHex.toUpperAscii == "#AABBCC"
    check color.fromHex("#001122FF").toHex.toUpperAscii == "#001122"
    # non-opaque: toHex keeps AA suffix
    check color.fromHex("#00000000").toHex.toUpperAscii == "#00000000"

# ---------------------------------------------------------------------------
# GFX-002: Alpha applied to stroke and fill in SVG
# ---------------------------------------------------------------------------

suite "GFX-002 Alpha in SVG output":
  setup:
    clearGraphics()

  test "opaque stroke color renders without alpha component":
    setStrokeColor(RED)           # alpha = 0xFF
    drawLine(0, 0, 10, 10)
    let svg = svgOutput()
    check svg.contains("stroke=\"#FF0000\"")

  test "semi-transparent stroke color includes alpha in hex":
    setStrokeColor(fromRgba(255, 0, 0, 128))
    drawLine(0, 0, 10, 10)
    let svg = svgOutput()
    check svg.contains("stroke=\"#FF000080\"")

  test "opaque fill color renders without alpha component":
    setFillColor(BLUE)
    fillCircle(5, 5, 3)
    let svg = svgOutput()
    check svg.contains("fill=\"#0000FF\"")

  test "semi-transparent fill color includes alpha in hex":
    setFillColor(fromRgba(0, 0, 255, 64))
    fillCircle(5, 5, 3)
    let svg = svgOutput()
    check svg.contains("fill=\"#0000FF40\"")

  test "SVG with alpha is well-formed XML":
    setStrokeColor(fromRgba(100, 200, 50, 128))
    drawLine(0, 0, 1, 1)
    discard parseXml(svgOutput())

# ---------------------------------------------------------------------------
# GFX-003: Text is escaped in SVG output
# ---------------------------------------------------------------------------

suite "GFX-003 Text XML escaping":
  setup:
    clearGraphics()

  test "drawText escapes > < &":
    drawText("Health: 50 > 25 & <alive>", 10.0, 20.0)
    let svg = svgOutput()
    check svg.contains("&gt;")
    check svg.contains("&amp;")
    check svg.contains("&lt;")
    check not svg.contains("<alive>")

  test "escaped SVG is well-formed XML":
    drawText("a > b & c < d", 0.0, 0.0)
    discard parseXml(svgOutput())

  test "plain text passes through unchanged":
    drawText("hello world", 0.0, 0.0)
    let svg = svgOutput()
    check svg.contains("hello world")

# ---------------------------------------------------------------------------
# GFX-004: Identical draw sequences produce identical SVG
# ---------------------------------------------------------------------------

suite "GFX-004 Deterministic SVG output":
  test "same draw sequence yields identical strings":
    clearGraphics()
    setStrokeColor(RED)
    drawLine(1.0, 2.0, 3.0, 4.0)
    setFillColor(BLUE)
    fillCircle(5.0, 5.0, 10.0)
    drawText("test", 0.0, 0.0)
    let svg1 = svgOutput()

    clearGraphics()
    setStrokeColor(RED)
    drawLine(1.0, 2.0, 3.0, 4.0)
    setFillColor(BLUE)
    fillCircle(5.0, 5.0, 10.0)
    drawText("test", 0.0, 0.0)
    let svg2 = svgOutput()

    check svg1 == svg2

  test "different draw sequences yield different strings":
    clearGraphics()
    drawLine(1.0, 2.0, 3.0, 4.0)
    let svgA = svgOutput()

    clearGraphics()
    drawLine(9.0, 8.0, 7.0, 6.0)
    let svgB = svgOutput()

    check svgA != svgB

  test "clearGraphics resets to empty output":
    clearGraphics()
    drawLine(0, 0, 1, 1)
    discard svgOutput()
    clearGraphics()
    check svgOutput() == ""
