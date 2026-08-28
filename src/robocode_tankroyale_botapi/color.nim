## Color type for Robocode Tank Royale — RGBA packed as uint32 (R<<24|G<<16|B<<8|A),
## matching the layout of the Java Color class.
##
## The `Color` type is a distinct `uint32` that stores RGBA values in a single
## 32-bit integer. This is the same format used by the Java `Color` class and
## the Tank Royale protocol.
##
## ## Creating Colors
##
## You can create colors in several ways:
##
## ```nim
## # From RGB values (0-255), alpha defaults to 255 (opaque)
## let red = fromRgb(255, 0, 0)
## 
## # From RGBA values (0-255)
## let semiTransparentBlue = fromRgba(0, 0, 255, 128)
## 
## # From hex string ("#RRGGBB" or "#RRGGBBAA")
## let green = fromHex("#00FF00")
## let transparent = fromHex("#00FF0080")
## 
## # Using named color constants (141 standard colors)
## let gold = GOLD
## let cyan = CYAN
## ```
##
## ## Using Colors in Your Bot
##
## Colors are used for bot appearance and debug graphics:
##
## ```nim
## # Set bot body colors (call in run() or onGameStarted)
## setBodyColor(RED)
## setTurretColor(YELLOW)
## setRadarColor(GREEN)
## 
## # Use in debug graphics
## setStrokeColor(WHITE)
## setFillColor(RED)
## drawCircle(getX(), getY(), 50)
## ```
##
## ## Color Components
##
## Access individual components:
##
## ```nim
## let c = fromRgb(255, 128, 64)
## echo c.r  # 255
## echo c.g  # 128
## echo c.b  # 64
## echo c.a  # 255 (default opaque)
## ```
##
## ## Hex Output
##
## Convert to hex string for sending to server:
##
## ```nim
## let c = RED
## echo c.toHex  # "#FF0000"
## echo $c       # same, uses stringify operator
## ```
##
## ## Named Color Constants
##
## All 141 standard Java/HTML color names are available as constants:
## `ALICE_BLUE`, `ANTIQUE_WHITE`, `AQUA`, `AQUAMARINE`, `AZURE`,
## `BEIGE`, `BISQUE`, `BLACK`, `BLANCHED_ALMOND`, `BLUE`, `BLUE_VIOLET`,
## `BROWN`, `BURLY_WOOD`, `CADET_BLUE`, `CHARTREUSE`, `CHOCOLATE`,
## `CORAL`, `CORNFLOWER_BLUE`, `CORNSILK`, `CRIMSON`, `CYAN`,
## `DARK_BLUE`, `DARK_CYAN`, `DARK_GOLDENROD`, `DARK_GRAY`, `DARK_GREEN`,
## `DARK_KHAKI`, `DARK_MAGENTA`, `DARK_OLIVE_GREEN`, `DARK_ORANGE`,
## `DARK_ORCHID`, `DARK_RED`, `DARK_SALMON`, `DARK_SEA_GREEN`,
## `DARK_SLATE_BLUE`, `DARK_SLATE_GRAY`, `DARK_TURQUOISE`, `DARK_VIOLET`,
## `DEEP_PINK`, `DEEP_SKY_BLUE`, `DIM_GRAY`, `DODGER_BLUE`, `FIREBRICK`,
## `FLORAL_WHITE`, `FOREST_GREEN`, `FUCHSIA`, `GAINSBORO`, `GHOST_WHITE`,
## `GOLD`, `GOLDENROD`, `GRAY`, `GREEN`, `GREEN_YELLOW`, `HONEYDEW`,
## `HOT_PINK`, `INDIAN_RED`, `INDIGO`, `IVORY`, `KHAKI`, `LAVENDER`,
## `LAVENDER_BLUSH`, `LAWN_GREEN`, `LEMON_CHIFFON`, `LIGHT_BLUE`,
## `LIGHT_CORAL`, `LIGHT_CYAN`, `LIGHT_GOLDENROD_YELLOW`, `LIGHT_GRAY`,
## `LIGHT_GREEN`, `LIGHT_PINK`, `LIGHT_SALMON`, `LIGHT_SEA_GREEN`,
## `LIGHT_SKY_BLUE`, `LIGHT_SLATE_GRAY`, `LIGHT_STEEL_BLUE`, `LIGHT_YELLOW`,
## `LIME`, `LIME_GREEN`, `LINEN`, `MAGENTA`, `MAROUN`, `MEDIUM_AQUAMARINE`,
## `MEDIUM_BLUE`, `MEDIUM_ORCHID`, `MEDIUM_PURPLE`, `MEDIUM_SEA_GREEN`,
## `MEDIUM_SLATE_BLUE`, `MEDIUM_SPRING_GREEN`, `MEDIUM_TURQUOISE`,
## `MEDIUM_VIOLET_RED`, `MIDNIGHT_BLUE`, `MINT_CREAM`, `MISTY_ROSE`,
## `MOCCASIN`, `NAVAJO_WHITE`, `NAVY`, `OLD_LACE`, `OLIVE`, `OLIVE_DRAB`,
## `ORANGE`, `ORANGE_RED`, `ORCHID`, `PALE_GOLDENROD`, `PALE_GREEN`,
## `PALE_TURQUOISE`, `PALE_VIOLET_RED`, `PAPAYA_WHIP`, `PEACH_PUFF`,
## `PERU`, `PINK`, `PLUM`, `POWDER_BLUE`, `PURPLE`, `RED`, `ROSY_BROWN`,
## `ROYAL_BLUE`, `SADDLE_BROWN`, `SALMON`, `SANDY_BROWN`, `SEA_GREEN`,
## `SEA_SHELL`, `SIENNA`, `SILVER`, `SKY_BLUE`, `SLATE_BLUE`, `SLATE_GRAY`,
## `SNOW`, `SPRING_GREEN`, `STEEL_BLUE`, `TAN`, `TEAL`, `THISTLE`,
## `TOMATO`, `TURQUOISE`, `VIOLET`, `WHEAT`, `WHITE`, `WHITE_SMOKE`,
## `YELLOW`, `YELLOW_GREEN`, and `TRANSPARENT`.
##
## ## Implicit Conversion
##
## Strings are implicitly converted to `Color` via `fromHex`:
##
## ```nim
## setBodyColor("#FF0000")  # Works! Same as setBodyColor(fromHex("#FF0000"))
## setBodyColor("RED")      # Also works for named colors
## ```
##
import std/strutils

type Color* = distinct uint32

# ---------------------------------------------------------------------------
# Factory procs
# ---------------------------------------------------------------------------

proc fromRgb*(r, g, b: uint8): Color {.inline.} =
  ## Create a color from RGB components (alpha = 255, fully opaque).
  ##
  ## Parameters:
  ## - `r`: Red component (0-255)
  ## - `g`: Green component (0-255)
  ## - `b`: Blue component (0-255)
  ##
  ## Returns: Opaque color with the given RGB values
  Color((r.uint32 shl 24) or (g.uint32 shl 16) or (b.uint32 shl 8) or 0xFF)

proc fromRgba*(r, g, b, a: uint8): Color {.inline.} =
  ## Create a color from RGBA components.
  ##
  ## Parameters:
  ## - `r`: Red component (0-255)
  ## - `g`: Green component (0-255)
  ## - `b`: Blue component (0-255)
  ## - `a`: Alpha component (0-255), 0 = transparent, 255 = opaque
  ##
  ## Returns: Color with the given RGBA values
  Color((r.uint32 shl 24) or (g.uint32 shl 16) or (b.uint32 shl 8) or a.uint32)

proc fromHex*(s: string): Color =
  ## Parse a hex color string.
  ##
  ## Accepts formats:
  ## - `#RRGGBB` (6 hex digits, alpha = 255)
  ## - `#RRGGBBAA` (8 hex digits, includes alpha)
  ## - `RRGGBB` or `RRGGBBAA` (leading `#` optional)
  ##
  ## Parameters:
  ## - `s`: Hex color string
  ##
  ## Returns: Parsed color
  ##
  ## Raises: `ValueError` if the string format is invalid
  let h = if s.len > 0 and s[0] == '#': s[1..^1] else: s
  case h.len
  of 6:
    let v = parseHexInt(h)
    result = Color((v.uint32 shl 8) or 0xFF)
  of 8:
    result = Color(parseHexInt(h).uint32)
  else:
    raise newException(ValueError, "invalid color string: " & s)

# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------

proc r*(c: Color): uint8 {.inline.} =
  ## Get the red component (0-255).
  uint8(c.uint32 shr 24)

proc g*(c: Color): uint8 {.inline.} =
  ## Get the green component (0-255).
  uint8((c.uint32 shr 16) and 0xFF)

proc b*(c: Color): uint8 {.inline.} =
  ## Get the blue component (0-255).
  uint8((c.uint32 shr 8) and 0xFF)

proc a*(c: Color): uint8 {.inline.} =
  ## Get the alpha component (0-255). 0 = transparent, 255 = opaque.
  uint8(c.uint32 and 0xFF)

# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

proc toHex*(c: Color): string =
  ## Convert color to hex string.
  ##
  ## Returns `#RRGGBB` for opaque colors (alpha=255),
  ## `#RRGGBBAA` for colors with transparency.
  ##
  ## This format is used by the Tank Royale protocol for bot colors.
  if c.a == 0xFF:
    result = '#' & toHex(c.r.int, 2) & toHex(c.g.int, 2) & toHex(c.b.int, 2)
  else:
    result = '#' & toHex(c.r.int, 2) & toHex(c.g.int, 2) & toHex(c.b.int, 2) & toHex(c.a.int, 2)

proc `$`*(c: Color): string =
  ## Stringify operator -- returns the same as `toHex()`.
  ##
  ## Allows using colors directly in string interpolation:
  ## ```nim
  ## echo "My color is " & $RED  # "My color is #FF0000"
  ## ```
  c.toHex

proc `==`*(a, b: Color): bool {.borrow.}
  ## Compare two colors for equality.
  ## Uses the underlying uint32 comparison.

# ---------------------------------------------------------------------------
# Backward compat: implicit conversion from string literal / variable
# ---------------------------------------------------------------------------

converter toColor*(s: string): Color =
  ## Implicitly convert a string to a Color.
  ##
  ## This allows passing hex strings or color names directly to procedures
  ## that expect a `Color`:
  ## ```nim
  ## setBodyColor("#FF0000")  # Hex string
  ## setBodyColor("RED")      # Named color (via fromHex)
  ## ```
  fromHex(s)

# ---------------------------------------------------------------------------
# Named constants (all 141 from Java Color class)
# ---------------------------------------------------------------------------

const
  TRANSPARENT*          = fromRgba(255, 255, 255, 0)
  ALICE_BLUE*           = fromRgb(240, 248, 255)
  ANTIQUE_WHITE*        = fromRgb(250, 235, 215)
  AQUA*                 = fromRgb(0, 255, 255)
  AQUAMARINE*           = fromRgb(127, 255, 212)
  AZURE*                = fromRgb(240, 255, 255)
  BEIGE*                = fromRgb(245, 245, 220)
  BISQUE*               = fromRgb(255, 228, 196)
  BLACK*                = fromRgb(0, 0, 0)
  BLANCHED_ALMOND*      = fromRgb(255, 235, 205)
  BLUE*                 = fromRgb(0, 0, 255)
  BLUE_VIOLET*          = fromRgb(138, 43, 226)
  BROWN*                = fromRgb(165, 42, 42)
  BURLY_WOOD*           = fromRgb(222, 184, 135)
  CADET_BLUE*           = fromRgb(95, 158, 160)
  CHARTREUSE*           = fromRgb(127, 255, 0)
  CHOCOLATE*            = fromRgb(210, 105, 30)
  CORAL*                = fromRgb(255, 127, 80)
  CORNFLOWER_BLUE*      = fromRgb(100, 149, 237)
  CORNSILK*             = fromRgb(255, 248, 220)
  CRIMSON*              = fromRgb(220, 20, 60)
  CYAN*                 = fromRgb(0, 255, 255)
  DARK_BLUE*            = fromRgb(0, 0, 139)
  DARK_CYAN*            = fromRgb(0, 139, 139)
  DARK_GOLDENROD*       = fromRgb(184, 134, 11)
  DARK_GRAY*            = fromRgb(169, 169, 169)
  DARK_GREEN*           = fromRgb(0, 100, 0)
  DARK_KHAKI*           = fromRgb(189, 183, 107)
  DARK_MAGENTA*         = fromRgb(139, 0, 139)
  DARK_OLIVE_GREEN*     = fromRgb(85, 107, 47)
  DARK_ORANGE*          = fromRgb(255, 140, 0)
  DARK_ORCHID*          = fromRgb(153, 50, 204)
  DARK_RED*             = fromRgb(139, 0, 0)
  DARK_SALMON*          = fromRgb(233, 150, 122)
  DARK_SEA_GREEN*       = fromRgb(143, 188, 139)
  DARK_SLATE_BLUE*      = fromRgb(72, 61, 139)
  DARK_SLATE_GRAY*      = fromRgb(47, 79, 79)
  DARK_TURQUOISE*       = fromRgb(0, 206, 209)
  DARK_VIOLET*          = fromRgb(148, 0, 211)
  DEEP_PINK*            = fromRgb(255, 20, 147)
  DEEP_SKY_BLUE*        = fromRgb(0, 191, 255)
  DIM_GRAY*             = fromRgb(105, 105, 105)
  DODGER_BLUE*          = fromRgb(30, 144, 255)
  FIREBRICK*            = fromRgb(178, 34, 34)
  FLORAL_WHITE*         = fromRgb(255, 250, 240)
  FOREST_GREEN*         = fromRgb(34, 139, 34)
  FUCHSIA*              = fromRgb(255, 0, 255)
  GAINSBORO*            = fromRgb(220, 220, 220)
  GHOST_WHITE*          = fromRgb(248, 248, 255)
  GOLD*                 = fromRgb(255, 215, 0)
  GOLDENROD*            = fromRgb(218, 165, 32)
  GRAY*                 = fromRgb(128, 128, 128)
  GREEN*                = fromRgb(0, 128, 0)
  GREEN_YELLOW*         = fromRgb(173, 255, 47)
  HONEYDEW*             = fromRgb(240, 255, 240)
  HOT_PINK*             = fromRgb(255, 105, 180)
  INDIAN_RED*           = fromRgb(205, 92, 92)
  INDIGO*               = fromRgb(75, 0, 130)
  IVORY*                = fromRgb(255, 255, 240)
  KHAKI*                = fromRgb(240, 230, 140)
  LAVENDER*             = fromRgb(230, 230, 250)
  LAVENDER_BLUSH*       = fromRgb(255, 240, 245)
  LAWN_GREEN*           = fromRgb(124, 252, 0)
  LEMON_CHIFFON*        = fromRgb(255, 250, 205)
  LIGHT_BLUE*           = fromRgb(173, 216, 230)
  LIGHT_CORAL*          = fromRgb(240, 128, 128)
  LIGHT_CYAN*           = fromRgb(224, 255, 255)
  LIGHT_GOLDENROD_YELLOW* = fromRgb(250, 250, 210)
  LIGHT_GRAY*           = fromRgb(211, 211, 211)
  LIGHT_GREEN*          = fromRgb(144, 238, 144)
  LIGHT_PINK*           = fromRgb(255, 182, 193)
  LIGHT_SALMON*         = fromRgb(255, 160, 122)
  LIGHT_SEA_GREEN*      = fromRgb(32, 178, 170)
  LIGHT_SKY_BLUE*       = fromRgb(135, 206, 250)
  LIGHT_SLATE_GRAY*     = fromRgb(119, 136, 153)
  LIGHT_STEEL_BLUE*     = fromRgb(176, 196, 222)
  LIGHT_YELLOW*         = fromRgb(255, 255, 224)
  LIME*                 = fromRgb(0, 255, 0)
  LIME_GREEN*           = fromRgb(50, 205, 50)
  LINEN*                = fromRgb(250, 240, 230)
  MAGENTA*              = fromRgb(255, 0, 255)
  MAROON*               = fromRgb(128, 0, 0)
  MEDIUM_AQUAMARINE*    = fromRgb(102, 205, 170)
  MEDIUM_BLUE*          = fromRgb(0, 0, 205)
  MEDIUM_ORCHID*        = fromRgb(186, 85, 211)
  MEDIUM_PURPLE*        = fromRgb(147, 112, 219)
  MEDIUM_SEA_GREEN*     = fromRgb(60, 179, 113)
  MEDIUM_SLATE_BLUE*    = fromRgb(123, 104, 238)
  MEDIUM_SPRING_GREEN*  = fromRgb(0, 250, 154)
  MEDIUM_TURQUOISE*     = fromRgb(72, 209, 204)
  MEDIUM_VIOLET_RED*    = fromRgb(199, 21, 133)
  MIDNIGHT_BLUE*        = fromRgb(25, 25, 112)
  MINT_CREAM*           = fromRgb(245, 255, 250)
  MISTY_ROSE*           = fromRgb(255, 228, 225)
  MOCCASIN*             = fromRgb(255, 228, 181)
  NAVAJO_WHITE*         = fromRgb(255, 222, 173)
  NAVY*                 = fromRgb(0, 0, 128)
  OLD_LACE*             = fromRgb(253, 245, 230)
  OLIVE*                = fromRgb(128, 128, 0)
  OLIVE_DRAB*           = fromRgb(107, 142, 35)
  ORANGE*               = fromRgb(255, 165, 0)
  ORANGE_RED*           = fromRgb(255, 69, 0)
  ORCHID*               = fromRgb(218, 112, 214)
  PALE_GOLDENROD*       = fromRgb(238, 232, 170)
  PALE_GREEN*           = fromRgb(152, 251, 152)
  PALE_TURQUOISE*       = fromRgb(175, 238, 238)
  PALE_VIOLET_RED*      = fromRgb(219, 112, 147)
  PAPAYA_WHIP*          = fromRgb(255, 239, 213)
  PEACH_PUFF*           = fromRgb(255, 218, 185)
  PERU*                 = fromRgb(205, 133, 63)
  PINK*                 = fromRgb(255, 192, 203)
  PLUM*                 = fromRgb(221, 160, 221)
  POWDER_BLUE*          = fromRgb(176, 224, 230)
  PURPLE*               = fromRgb(128, 0, 128)
  RED*                  = fromRgb(255, 0, 0)
  ROSY_BROWN*           = fromRgb(188, 143, 143)
  ROYAL_BLUE*           = fromRgb(65, 105, 225)
  SADDLE_BROWN*         = fromRgb(139, 69, 19)
  SALMON*               = fromRgb(250, 128, 114)
  SANDY_BROWN*          = fromRgb(244, 164, 96)
  SEA_GREEN*            = fromRgb(46, 139, 87)
  SEA_SHELL*            = fromRgb(255, 245, 238)
  SIENNA*               = fromRgb(160, 82, 45)
  SILVER*               = fromRgb(192, 192, 192)
  SKY_BLUE*             = fromRgb(135, 206, 235)
  SLATE_BLUE*           = fromRgb(106, 90, 205)
  SLATE_GRAY*           = fromRgb(112, 128, 144)
  SNOW*                 = fromRgb(255, 250, 250)
  SPRING_GREEN*         = fromRgb(0, 255, 127)
  STEEL_BLUE*           = fromRgb(70, 130, 180)
  TAN*                  = fromRgb(210, 180, 140)
  TEAL*                 = fromRgb(0, 128, 128)
  THISTLE*              = fromRgb(216, 191, 216)
  TOMATO*               = fromRgb(255, 99, 71)
  TURQUOISE*            = fromRgb(64, 224, 208)
  VIOLET*               = fromRgb(238, 130, 238)
  WHEAT*                = fromRgb(245, 222, 179)
  WHITE*                = fromRgb(255, 255, 255)
  WHITE_SMOKE*          = fromRgb(245, 245, 245)
  YELLOW*               = fromRgb(255, 255, 0)
  YELLOW_GREEN*         = fromRgb(154, 205, 50)
