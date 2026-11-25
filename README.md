# Glissade

A free menu-bar app for macOS that turns mouse-wheel notches into smooth glides.

- Three presets (Crisp, Balanced, Floaty), or set the distance, glide time,
  fast-spin boost and start yourself
- Reverse the mouse wheel without changing the trackpad
- Hold Shift to scroll sideways, click to stop a glide
- Leave chosen apps alone
- No network connections, analytics or accounts

Trackpads, Magic Mouse, and the wheel with Cmd, Ctrl or Option held are left alone.

## Install

You need macOS 14 or later and Apple's free Command Line Tools. Open Terminal:

1. Install the tools, if you don't have them:

   ```bash
   xcode-select --install
   ```

2. Download and build Glissade:

   ```bash
   git clone https://github.com/onlydukez/Glissade.git
   cd Glissade
   ./build.sh
   ```

3. Copy it to Applications and open it:

   ```bash
   cp -R build/Glissade.app /Applications/
   open /Applications/Glissade.app
   ```

4. Click **Allow…** in the Glissade window, then switch Glissade on in
   System Settings > Privacy & Security > Accessibility. macOS requires this
   for any app that changes scroll events.

If you use another app that changes mouse-wheel scrolling, quit it first.

## Update

Quit Glissade from its menu, delete it from Applications, run `git pull`, then
repeat steps 2 (only `./build.sh`) to 4. Builds are signed only for the Mac that
made them, so macOS treats each one as a new app. If Glissade still asks for
access, remove it from the Accessibility list and allow it again.

## Uninstall

Turn off "Open at login" in Glissade's settings, quit it, and delete it from
Applications. Then remove it from the Accessibility list.

## Development

```bash
./check.sh                                               # scroll physics
build/Glissade.app/Contents/MacOS/Glissade --self-test   # event handling
```

- `Sources/Core` – the scroll physics (a critically damped spring)
- `Sources/App` – event interception, settings window, menu
- `Checks` – physics checks
- `Tools` – draws the app icon
