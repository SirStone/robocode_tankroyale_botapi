## SVG debug graphics API for Robocode Tank Royale Nim bot API.
## Module-level procs write SVG into a buffer that is flushed into
## BotIntent.debugGraphics each tick and cleared afterward.

import std/strformat
import std/xmltree
import ./color

# ---------------------------------------------------------------------------
# Module-level state (single bot per process)
# ---------------------------------------------------------------------------

var gSvgBuffer:   string
var gStrokeColor: Color = WHITE
var gFillColor:   Color = WHITE
var gStrokeWidth: float = 1.0
var gFontFamily:  string = "Arial"  # never rebound at runtime (setFont unused)
var gFontSize:    float = 12.0

proc appendSvg(s: string) =
  gSvgBuffer.add s

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc svgAttrs(): string =
  ## Current stroke/fill/width as SVG attribute string.
  &"stroke=\"{gStrokeColor.toHex}\" fill=\"{gFillColor.toHex}\" stroke-width=\"{gStrokeWidth}\""

proc svgOutput*(): string =
  ## Returns the SVG fragment for this tick, or "" if nothing was drawn.
  if gSvgBuffer.len == 0: return ""
  "<g>" & gSvgBuffer & "</g>"

proc clearGraphics*() =
  ## Reset buffer and all style globals to defaults. Called after each tick.
  gSvgBuffer.setLen(0)
  gStrokeColor = WHITE
  gFillColor   = WHITE
  gStrokeWidth = 1.0
  gFontFamily  = "Arial"
  gFontSize    = 12.0

# ---------------------------------------------------------------------------
# State setters
# ---------------------------------------------------------------------------

proc setStrokeColor*(c: Color) = gStrokeColor = c
proc setFillColor*(c: Color)   = gFillColor   = c
proc setStrokeWidth*(w: float) = gStrokeWidth = w
proc setFont*(family: string; size: float) =
  gFontFamily = family
  gFontSize   = size

# ---------------------------------------------------------------------------
# Draw procs — append raw SVG elements
# ---------------------------------------------------------------------------

proc drawLine*(x1, y1, x2, y2: float) =
  appendSvg(&"<line x1=\"{x1}\" y1=\"{y1}\" x2=\"{x2}\" y2=\"{y2}\" {svgAttrs()}/>")

proc drawRectangle*(x, y, w, h: float) =
  let attrs = &"stroke=\"{gStrokeColor.toHex}\" fill=\"none\" stroke-width=\"{gStrokeWidth}\""
  appendSvg(&"<rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" {attrs}/>")

proc fillRectangle*(x, y, w, h: float) =
  let attrs = &"stroke=\"none\" fill=\"{gFillColor.toHex}\""
  appendSvg(&"<rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" {attrs}/>")

proc drawCircle*(x, y, r: float) =
  let attrs = &"stroke=\"{gStrokeColor.toHex}\" fill=\"none\" stroke-width=\"{gStrokeWidth}\""
  appendSvg(&"<circle cx=\"{x}\" cy=\"{y}\" r=\"{r}\" {attrs}/>")

proc fillCircle*(x, y, r: float) =
  let attrs = &"stroke=\"none\" fill=\"{gFillColor.toHex}\""
  appendSvg(&"<circle cx=\"{x}\" cy=\"{y}\" r=\"{r}\" {attrs}/>")

proc drawText*(text: string; x, y: float) =
  appendSvg(&"<text x=\"{x}\" y=\"{y}\" font-family=\"{escape(gFontFamily)}\" font-size=\"{gFontSize}\">{escape(text)}</text>")

proc drawPolygon*(points: seq[(float, float)]) =
  var pts = ""
  for (px, py) in points:
    if pts.len > 0: pts.add ' '
    pts.add &"{px},{py}"
  let attrs = &"stroke=\"{gStrokeColor.toHex}\" fill=\"none\" stroke-width=\"{gStrokeWidth}\""
  appendSvg(&"<polygon points=\"{pts}\" {attrs}/>")

proc fillPolygon*(points: seq[(float, float)]) =
  var pts = ""
  for (px, py) in points:
    if pts.len > 0: pts.add ' '
    pts.add &"{px},{py}"
  let attrs = &"stroke=\"none\" fill=\"{gFillColor.toHex}\""
  appendSvg(&"<polygon points=\"{pts}\" {attrs}/>")
