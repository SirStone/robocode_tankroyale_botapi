## SVG debug graphics API for Robocode Tank Royale Nim bot API.
##
## This module provides a simple way to draw debug graphics (lines, circles,
## rectangles, text, polygons) that are sent to the server each tick and
## rendered in the Robocode Tank Royale viewer. This is extremely useful for
## visualizing your bot's decision-making: target lines, predicted positions,
## radar coverage, etc.
##
## ## How It Works
##
## 1. Call drawing procedures (`drawLine`, `drawCircle`, `drawText`, etc.)
##    in your bot's `run()` method or event handlers.
## 2. Set styles beforehand with `setStrokeColor`, `setFillColor`,
##    `setStrokeWidth`, `setFont`.
## 3. At the end of each tick, the SVG buffer is automatically sent to the
##    server via `BotIntent.debugGraphics` and then cleared.
## 4. The viewer renders the SVG overlay on the battlefield.
##
## ## Basic Example
##
## ```nim
## method run(bot: MyBot) =
##   while true:
##     # Draw a line to the nearest enemy
##     if getEnemyCount() > 0:
##       setStrokeColor(RED)
##       setStrokeWidth(2.0)
##       drawLine(getX(), getY(), enemyX, enemyY)
##     
##     # Draw radar coverage
##     setStrokeColor(GREEN)
##     setStrokeWidth(1.0)
##     drawCircle(getX(), getY(), RADAR_RADIUS)
##     
##     # Draw text label
##     setFillColor(WHITE)
##     setFont("Arial", 14)
##     drawText("Hunting!", getX() + 20, getY() - 20)
##     
##     go()
## ```
##
## ## Coordinate System
##
## The coordinate system matches the game: (0, 0) is top-left, X increases
## right, Y increases down. The arena size is available via `getArenaWidth()`
## and `getArenaHeight()`.
##
## ## Style State
##
## Style settings persist across drawing calls until changed:
##
## - `setStrokeColor` / `setFillColor` -- Colors for outlines and fills
## - `setStrokeWidth` -- Line thickness
## - `setFont` -- Font family and size for text
##
## All styles are reset to defaults after each tick (in `clearGraphics`).
##
## ## See Also
##
## - `bot.setBodyColor` etc. -- Set your bot's actual body colors
## - `color` module -- Color constants and creation

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
  ## Internal: append raw SVG to the buffer.
  gSvgBuffer.add s

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

proc svgAttrs(): string =
  ## Current stroke/fill/width as SVG attribute string.
  &"stroke=\"{gStrokeColor.toHex}\" fill=\"{gFillColor.toHex}\" stroke-width=\"{gStrokeWidth}\""

proc svgOutput*(): string =
  ## Returns the SVG fragment for this tick, or "" if nothing was drawn.
  ##
  ## Called automatically by the API at the end of each tick to include
  ## debug graphics in the BotIntent sent to the server.
  if gSvgBuffer.len == 0: return ""
  "<g>" & gSvgBuffer & "</g>"

proc clearGraphics*() =
  ## Reset buffer and all style globals to defaults. Called after each tick.
  ##
  ## You don't need to call this manually -- it's called automatically
  ## at the start of each tick.
  gSvgBuffer.setLen(0)
  gStrokeColor = WHITE
  gFillColor   = WHITE
  gStrokeWidth = 1.0
  gFontFamily  = "Arial"
  gFontSize    = 12.0

# ---------------------------------------------------------------------------
# State setters
# ---------------------------------------------------------------------------

proc setStrokeColor*(c: Color) =
  ## Set the stroke (outline) color for subsequent drawing operations.
  ##
  ## Parameters:
  ## - `c`: Color to use for outlines
  ##
  ## Example:
  ## ```nim
  ## setStrokeColor(RED)
  ## drawLine(0, 0, 100, 100)  # Red line
  ## ```
  gStrokeColor = c

proc setFillColor*(c: Color) =
  ## Set the fill color for subsequent drawing operations.
  ##
  ## Parameters:
  ## - `c`: Color to use for fills
  ##
  ## Example:
  ## ```nim
  ## setFillColor(BLUE)
  ## fillCircle(50, 50, 25)  # Blue filled circle
  ## ```
  gFillColor = c

proc setStrokeWidth*(w: float) =
  ## Set the stroke width (line thickness) for subsequent drawing operations.
  ##
  ## Parameters:
  ## - `w`: Line width in game units
  ##
  ## Example:
  ## ```nim
  ## setStrokeWidth(3.0)
  ## drawCircle(100, 100, 50)  # Thick circle outline
  ## ```
  gStrokeWidth = w

proc setFont*(family: string; size: float) =
  ## Set the font family and size for text drawing.
  ##
  ## Parameters:
  ## - `family`: Font family name (e.g., "Arial", "monospace")
  ## - `size`: Font size in pixels
  ##
  ## Example:
  ## ```nim
  ## setFont("monospace", 16)
  ## drawText("Debug info", 10, 20)
  ## ```
  gFontFamily = family
  gFontSize   = size

# ---------------------------------------------------------------------------
# Draw procs — append raw SVG elements
# ---------------------------------------------------------------------------

proc drawLine*(x1, y1, x2, y2: float) =
  ## Draw a line from (x1, y1) to (x2, y2) using current stroke color/width.
  ##
  ## Parameters:
  ## - `x1`, `y1`: Start point
  ## - `x2`, `y2`: End point
  ##
  ## Example:
  ## ```nim
  ## setStrokeColor(RED)
  ## setStrokeWidth(2.0)
  ## drawLine(getX(), getY(), targetX, targetY)
  ## ```
  appendSvg(&"<line x1=\"{x1}\" y1=\"{y1}\" x2=\"{x2}\" y2=\"{y2}\" {svgAttrs()}/>")

proc drawRectangle*(x, y, w, h: float) =
  ## Draw a rectangle outline at (x, y) with width w and height h.
  ##
  ## Uses current stroke color and width. No fill.
  ##
  ## Parameters:
  ## - `x`, `y`: Top-left corner
  ## - `w`: Width
  ## - `h`: Height
  let attrs = &"stroke=\"{gStrokeColor.toHex}\" fill=\"none\" stroke-width=\"{gStrokeWidth}\""
  appendSvg(&"<rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" {attrs}/>")

proc fillRectangle*(x, y, w, h: float) =
  ## Draw a filled rectangle at (x, y) with width w and height h.
  ##
  ## Uses current fill color. No stroke.
  ##
  ## Parameters:
  ## - `x`, `y`: Top-left corner
  ## - `w`: Width
  ## - `h`: Height
  let attrs = &"stroke=\"none\" fill=\"{gFillColor.toHex}\""
  appendSvg(&"<rect x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" {attrs}/>")

proc drawCircle*(x, y, r: float) =
  ## Draw a circle outline at (x, y) with radius r.
  ##
  ## Uses current stroke color and width. No fill.
  ##
  ## Parameters:
  ## - `x`, `y`: Center point
  ## - `r`: Radius
  ##
  ## Example:
  ## ```nim
  ## setStrokeColor(GREEN)
  ## drawCircle(getX(), getY(), RADAR_RADIUS)  # Radar range
  ## ```
  let attrs = &"stroke=\"{gStrokeColor.toHex}\" fill=\"none\" stroke-width=\"{gStrokeWidth}\""
  appendSvg(&"<circle cx=\"{x}\" cy=\"{y}\" r=\"{r}\" {attrs}/>")

proc fillCircle*(x, y, r: float) =
  ## Draw a filled circle at (x, y) with radius r.
  ##
  ## Uses current fill color. No stroke.
  ##
  ## Parameters:
  ## - `x`, `y`: Center point
  ## - `r`: Radius
  let attrs = &"stroke=\"none\" fill=\"{gFillColor.toHex}\""
  appendSvg(&"<circle cx=\"{x}\" cy=\"{y}\" r=\"{r}\" {attrs}/>")

proc drawText*(text: string; x, y: float) =
  ## Draw text at (x, y) using current fill color, font family, and size.
  ##
  ## The text baseline is at y (SVG default). For top-aligned text,
  ## add the font size to y.
  ##
  ## Parameters:
  ## - `text`: Text to draw
  ## - `x`, `y`: Position
  ##
  ## Example:
  ## ```nim
  ## setFillColor(WHITE)
  ## setFont("Arial", 14)
  ## drawText("Target locked!", getX() + 20, getY() - 20)
  ## ```
  appendSvg(&"<text x=\"{x}\" y=\"{y}\" font-family=\"{escape(gFontFamily)}\" font-size=\"{gFontSize}\">{escape(text)}</text>")

proc drawPolygon*(points: seq[(float, float)]) =
  ## Draw a polygon outline from a sequence of points.
  ##
  ## Uses current stroke color and width. No fill.
  ## The polygon is automatically closed (last point connects to first).
  ##
  ## Parameters:
  ## - `points`: Sequence of (x, y) tuples
  ##
  ## Example:
  ## ```nim
  ## setStrokeColor(YELLOW)
  ## drawPolygon(@[(0, 0), (10, 0), (5, 10)])  # Triangle
  ## ```
  var pts = ""
  for (px, py) in points:
    if pts.len > 0: pts.add ' '
    pts.add &"{px},{py}"
  let attrs = &"stroke=\"{gStrokeColor.toHex}\" fill=\"none\" stroke-width=\"{gStrokeWidth}\""
  appendSvg(&"<polygon points=\"{pts}\" {attrs}/>")

proc fillPolygon*(points: seq[(float, float)]) =
  ## Draw a filled polygon from a sequence of points.
  ##
  ## Uses current fill color. No stroke.
  ## The polygon is automatically closed (last point connects to first).
  ##
  ## Parameters:
  ## - `points`: Sequence of (x, y) tuples
  var pts = ""
  for (px, py) in points:
    if pts.len > 0: pts.add ' '
    pts.add &"{px},{py}"
  let attrs = &"stroke=\"none\" fill=\"{gFillColor.toHex}\""
  appendSvg(&"<polygon points=\"{pts}\" {attrs}/>")
