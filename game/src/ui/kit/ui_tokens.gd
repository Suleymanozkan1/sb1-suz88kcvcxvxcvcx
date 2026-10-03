class_name UiTokens
extends RefCounted
## Design tokens for the UI system (docs/ART_DIRECTION.md §10).
## Reference canvas 720 x 1280; everything snaps to an 8 px unit.

const UNIT: int = 8
const MARGIN: int = 32
const GUTTER: int = 16
const RADIUS: int = 4
const HAIRLINE: int = 1
const STROKE: int = 2

## Touch sizes: the 720-wide canvas spans a phone's width, so on a 390 pt /
## 412 dp phone one canvas px is about 0.54 pt. 88 px is about 48 pt, at or
## above the iOS (44 pt) and Android (48 dp) minimum touch targets.
const BUTTON_HEIGHT_PRIMARY: int = 96
const BUTTON_HEIGHT: int = 88
const ICON_BUTTON: int = 88
const ICON_SIZE: int = 28
const MIN_TOUCH: int = 88

## Typography scale: [size, weight].
const H1: Array[int] = [64, 800]
const H2: Array[int] = [40, 800]
const H3: Array[int] = [28, 600]
const BODY: Array[int] = [24, 400]
const CAPTION: Array[int] = [18, 600]
const SCORE: Array[int] = [72, 800]
const BUTTON: Array[int] = [26, 800]
const REWARD: Array[int] = [44, 800]

## Tracking (letter spacing, px) for upper-case styles.
const TRACK_CAPTION: int = 2
const TRACK_BUTTON: int = 2
const TRACK_H1: int = -1

## Surfaces and text (roles from Palette).
const SURFACE: Color = Palette.GRAPHITE
const SURFACE_RAISED: Color = Color("#202634")
const SURFACE_PRESSED: Color = Color("#151a23")
const BORDER: Color = Palette.SLATE
const TEXT: Color = Palette.BONE
const TEXT_MUTED: Color = Palette.FOG
const TEXT_ON_PRIMARY: Color = Palette.INK
const SCRIM: Color = Color(0.043, 0.055, 0.078, 0.82)

## Motion (seconds) — ART_DIRECTION §8.
const PRESS_TIME: float = 0.06
const RELEASE_TIME: float = 0.14
const SCREEN_TIME: float = 0.22
const SCREEN_SLIDE: float = 24.0
const STAR_INTERVAL: float = 0.12
const COUNT_UP_TIME: float = 0.6


static func u(n: float) -> int:
	return int(n * float(UNIT))
