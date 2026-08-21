## Color type for Robocode Tank Royale — RGBA packed as uint32 (R<<24|G<<16|B<<8|A),
## matching the layout of the Java Color class.

import std/strutils

type Color* = distinct uint32

# ---------------------------------------------------------------------------
# Factory procs
# ---------------------------------------------------------------------------

proc fromRgb*(r, g, b: uint8): Color {.inline.} =
  Color((r.uint32 shl 24) or (g.uint32 shl 16) or (b.uint32 shl 8) or 0xFF)

proc fromRgba*(r, g, b, a: uint8): Color {.inline.} =
  Color((r.uint32 shl 24) or (g.uint32 shl 16) or (b.uint32 shl 8) or a.uint32)

proc fromHex*(s: string): Color =
  ## Parse "#RRGGBB" or "#RRGGBBAA".  Raises ValueError on bad input.
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

proc r*(c: Color): uint8 {.inline.} = uint8(c.uint32 shr 24)
proc g*(c: Color): uint8 {.inline.} = uint8((c.uint32 shr 16) and 0xFF)
proc b*(c: Color): uint8 {.inline.} = uint8((c.uint32 shr 8) and 0xFF)
proc a*(c: Color): uint8 {.inline.} = uint8(c.uint32 and 0xFF)

# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

proc toHex*(c: Color): string =
  ## Returns "#RRGGBB" when alpha=255, "#RRGGBBAA" otherwise.
  if c.a == 0xFF:
    result = '#' & toHex(c.r.int, 2) & toHex(c.g.int, 2) & toHex(c.b.int, 2)
  else:
    result = '#' & toHex(c.r.int, 2) & toHex(c.g.int, 2) & toHex(c.b.int, 2) & toHex(c.a.int, 2)

proc `$`*(c: Color): string = c.toHex

proc `==`*(a, b: Color): bool {.borrow.}

# ---------------------------------------------------------------------------
# Backward compat: implicit conversion from string literal / variable
# ---------------------------------------------------------------------------

converter toColor*(s: string): Color = fromHex(s)

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
