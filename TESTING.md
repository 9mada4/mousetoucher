# Mouse Toucher testing

Mouse Toucher's automated tests focus on the pure gesture-recognition and click-sequence logic. The private MultitouchSupport framework and generated macOS click events still require manual testing on a real Magic Mouse.

## Run the tests

```bash
./run_tests.sh
```

The test runner uses only `swiftc`, so Apple's Command Line Tools are sufficient; installing the full Xcode application is not required.

The suite currently checks:

- a single finger never produces a click
- anchor plus a left- or right-side tap produces the correct button
- the same anchor can remain down, drift, and be reused for consecutive clicks
- three fingers begin a drag immediately and lifting every finger ends the drag
- mouse movement maps to continuous dragged events while a drag is active
- two-finger expansion and contraction produce continuous native magnification values
- simultaneous two-finger contact can begin pinch without becoming an accidental click
- disabling or cancelling pinch safely ends the native magnification sequence
- disabling three-finger drag rejects the gesture and reports the reason
- adjustable thresholds and the left/right boundary are applied correctly
- finger movement or partial contact loss does not interrupt an active drag
- cancelling or disabling always releases an active drag
- finger movement, anchor movement, and replacement touches are rejected with a visible reason
- invalid gestures require a clean release before recognition resumes
- OS-version presets persist, follow the detected system version, and use the chosen default after an OS change
- compatibility defaults to the appropriate OS path and explicit macOS 26/27 overrides are respected
- old presets migrate without losing tuning, and a saved legacy selection remains available on macOS 27
- changing compatibility ends an active drag exactly once
- the macOS 27 transport uses the HID tap before WindowServer; macOS 26 retains the session tap
- the modern drag source allows hardware mouse and keyboard events during synthetic dragging
- drag conversion preserves coordinates (including negative display coordinates), motion deltas, timestamp, modifiers, and button/source pairing
- title-bar detection excludes interactive controls and document content
- direct window movement uses absolute pointer displacement, stops after release or a failed position write, and never retargets a different window mid-gesture
- consecutive click counts increment for double- and multi-clicks
- changing the button, waiting too long, moving the cursor, or resetting starts a new click sequence

## Build checks

Compile the pure Swift package:

```bash
swift build
```

Build the complete universal macOS application:

```bash
./build.sh
```

The application build compiles both Apple Silicon and Intel binaries, combines them into `build/MouseToucher 2.2.app`, embeds the generated `AppIcon.icns`, and applies an ad-hoc signature.

For macOS 27 Command Line Tools without Intel Swift compatibility libraries, build the local Apple Silicon app with `ARCHS=arm64 ./build.sh`. Verify the actual output with `lipo -info "build/MouseToucher 2.2.app/Contents/MacOS/MouseToucher 2.2"`. The included build uses arm64; universal compilation must be checked with a toolchain providing the Intel runtime libraries.

## Manual Magic Mouse checklist

- The menu-bar icon appears and the enable/disable control works.
- Choosing Restart from the menu closes the current process and launches one new MouseToucher process.
- Finder and Accessibility settings show the MouseToucher app icon rather than a generic application icon.
- The Settings window opens and changes are saved without rebuilding.
- The displayed current macOS version matches `sw_vers`, and its exact preset is marked as current.
- Adding an arbitrary past or future OS preset, marking it as default, and applying it to the current OS all work.
- In the current preset, switch **ドラッグ互換性** between automatic, macOS 26, and macOS 27. Confirm **ドラッグ入力** changes immediately, then restart and check the choice persists. Editing another preset must not change the active mode until it is applied.
- On macOS 27, use automatic or macOS 27 compatibility. Place the pointer on a Finder or another app's draggable title-bar area, place three fingers on the Magic Mouse, and move the physical mouse. The **window itself** must follow continuously and stop when all fingers lift. Repeat across displays and after partial finger release. File dragging alone does not validate this regression.
- In both modes, check ordinary file dragging, text selection, two-finger clicks, and pinch zoom. Repeat the original behavior checks on a macOS 26 machine when available.
- Switch compatibility or disable the app during a drag; the held button must release. If input monitoring cannot start, Settings must report it and no synthetic button-down should be sent.
- The live status updates touch count, gesture state, recognized operation, and cancellation reason.
- In Safari or Preview, spreading two fingers zooms in smoothly and bringing them together zooms out smoothly.
- Pinching does not leak an ordinary scroll event into the target application.
- Releasing either pinch finger sends an ended phase and leaves the next tap responsive.
- The launch-at-login switch registers and unregisters the app on macOS 13 or later.
- A single finger resting, tapping, or scrolling does not click.
- Hold one finger still and tap the left half with a second finger: one left-click occurs.
- Hold one finger still and tap the right half with a second finger: one right-click occurs.
- Repeat the second-finger tap while keeping the anchor down: double-click and multi-click actions work.
- Place three fingers, move the mouse immediately, then lift every finger: the item follows continuously during movement and drops without jumping only at the end.
- Moving either finger during a two-finger click cancels only that click; the anchor can stay down for another attempt.
- Finger movement or partial contact loss after a three-finger drag begins does not release the dragged item.
- Adding a third finger begins a drag when three-finger drag is enabled.
- Pressing the physical mouse button cancels the gesture but still performs the normal physical click.
- Disabling compound tap prevents synthesized clicks immediately.
- Quitting and relaunching the installed application preserves Accessibility permission.

## Scope

For the direct title-bar path, first test a standard Finder title bar and MouseToucher's Settings title bar. After the gesture, **最後のドラッグ方式** should say **タイトルバー：ウィンドウ位置を直接移動**. Test the center of the title bar, away from buttons and tabs. Confirm files and text still drag normally; test changing compatibility, disabling the app, quitting, and pressing the physical mouse button during movement. No synthetic button-down/up is sent for direct window movement. Native edge snapping and dragging between Spaces are outside this path's scope.

Automated tests do not post real click events or connect to MultitouchSupport. Those integrations depend on macOS Accessibility permission, the connected mouse, and Apple's private framework, so they are covered by the manual checklist above.

The transport and event-shape tests do not prove that a real window moves. Complete the title-bar test above after granting Accessibility permission to the newly named app. macOS 26 behavior requires validation on macOS 26 hardware; selecting its compatibility mode on macOS 27 only checks the legacy code path.
