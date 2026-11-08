# Kith brand

*Kith* is the old word for the people you know. The design should feel like that: warm, quiet and
trustworthy, closer to paper and ink than to a dashboard. Colour is never decoration in Kith; each
one means the same thing everywhere it appears.

## The mark

A lowercase **k** whose raised arm reaches toward an amber dot: someone you know, waving. The dot is
also the moment Kith waits for your OK, the one colour the agent can't decide on its own.

| File | Use |
|---|---|
| `icon-ios.svg` | iOS app icon, full bleed (the system masks it) |
| `icon-mac.svg` | macOS app icon, on the 824 px squircle inside the 1024 px canvas |
| `mark-paper.svg` | The glyph alone, for dark grounds |
| `mark-template.svg` | One colour, for the menu bar (`MenuBarMark`, a template image) |

In the app the mark is drawn as vectors (`KithMark`, `KithGlyph`, `KithDot` in
`App/Shared/Views/Theme.swift`) on the same 1024 grid, so it stays sharp at any size. The PNGs in
`App/Shared/Assets.xcassets` are exported from these SVGs.

Geometry (1024 grid): stem from (356, 300) to (356, 730); arm from (356, 604) to (538, 443);
leg from (474, 508) to (640, 730); stroke 118 with round caps; dot centred at (652, 322), radius 86.

## Colour

Light and dark values; the app resolves them with the system appearance.

| Token | Light | Dark | Means |
|---|---|---|---|
| `kithPaper` | `#F5F1E8` | `#111815` | The window |
| `kithSurface` | `#FFFDF8` | `#19221E` | Cards, the composer |
| `kithSunken` | `#EDE7DA` | `#0C110F` | Wells: trace summary, raw values |
| `kithLine` | `#E2DACB` | `#27332D` | Hairlines |
| `kithInk` | `#18241E` | `#EEF0EA` | Text |
| `kithMuted` | `#5E6A62` | `#9AA8A0` | Secondary text |
| `kithMoss` | `#2F6E57` | `#5FB394` | Kith itself, your messages, actions, **on this device** |
| `kithLeaf` | `#2E8A5E` | `#6CC596` | **Checked** against your data |
| `kithAmber` | `#C27E16` | `#F0B456` | **Waiting for your OK** |
| `kithCoral` | `#C4502C` | `#F08766` | **Stopped**: blocked, refused, withheld |
| `kithDusk` | `#4F5BC4` | `#8E99F2` | Answered on **your Mac** |
| `kithClay` | `#B8613B` | `#E79A74` | Answered by **Claude** |

The three tiers keep their colour in the welcome, the answer footer and the trace, so where an answer
ran is visible before you read a word. The icon's gradient runs `#3C8068` to `#22503F` and the dot is
`#E9A23B`.

## Type

SF Pro throughout. Titles use SF Pro Rounded, bold (`Font.kithDisplay`), for a friendlier voice than
the default; everything else is the system text styles, so Dynamic Type works. Figures in the footer
and the trace are monospaced digits.

## Shapes

Continuous corners: 16 for cards, 14 for suggestion and promise cards, 22 for the composer, capsules
for chips and buttons. One hairline (`kithLine`) per card, no shadows except a soft one under the
composer. The main action is a moss capsule (`KithProminentButtonStyle`); its partner is quiet
(`KithQuietButtonStyle`).

## Screenshots

Debug builds can capture their own window with real answers, for the README and the portfolio. See
`App/Shared/DemoCapture.swift`.
