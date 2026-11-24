# MyRetroTVs (Unofficial)

An unofficial iPhone app for [MyRetroTVs](https://www.myretrotvs.com), the free retro TV simulator: channel-surf commercials, music videos, news and cartoons from the 1950s to the 2010s.

**Not made by or affiliated with MyRetroTVs.** Every TV set and clip comes from myretrotvs.com and YouTube. If you enjoy it, [support MyRetroTVs](https://www.buymeacoffee.com/myretrotvs).

## What the app adds

- **Living-room home screen:** seven drawn TV sets, one per decade, plus a "Back to the 80s" card for the last set you watched.
- **Native remote:** Power, CH and VOL rockers (VOL changes the iPhone volume, since iOS blocks web video volume), Menu, Full, an LED readout, and a decade dial. Every press has a haptic click.
- **Full screen:** the Full button stretches the video over the whole screen; tap the picture for a floating remote.
- **Guide:** what's playing now (title and channel), every year of the decade to jump to, and the site's content categories (Cartoons, Commercials, Music...) as switches. The clip title also scrolls under the TV.
- **Gestures:** swipe up/down on the TV to change channels (in Focus mode), and left/right to change decades.
- **Picture & Sound panel:** noise, glow, static, full-screen, playlist, shuffle and sound effects, plus black & white and room color on the 70s set.
- **Landscape:** turn the phone for a full-screen TV, with a pop-up remote.
- **Focus mode:** each set opens in the site's Immersive Mode, so you see just the TV. This can be turned off in Picture & Sound.
- Switch-on flash, static while a channel tunes, a no-signal screen with retry, sound that plays with the silent switch on, and a screen that stays awake while the TV is on.

The remote works by pressing the site's own keyboard shortcuts for you; the guide reads the page and uses the site's own year bar and filters. The TV's status messages show as banners.

## Download

```
https://github.com/hotwheelz3000/myretrotvs-app/releases/latest
```

The IPA is unsigned. Sign it when installing, for example with Signulous, Sideloadly or AltStore.

## Build

Built with [xtool](https://xtool.sh) (SwiftPM, no Xcode project) on GitHub Actions. Every push to `main` builds the IPA and publishes it as the `latest` release. The app icon is drawn by `scripts/make-app-icon.py`.
