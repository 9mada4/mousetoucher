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
- the default three-finger drag continues through partial contact loss and ends when all fingers lift
- the optional tap release mode keeps a drag active across empty frames; a fresh isolated single-finger tap ends it exactly once without a click
- the combined release mode also ends a drag when an anchor finger remains down and another finger taps
- long holds, movement, replacement touch IDs, and adding another finger invalidate the drop tap
- after a drop, ordinary clicking and the next three-finger drag work again
- periodic device refresh is deferred throughout a latched drag and resumes after release
- a drag beginning during device enumeration also prevents callback replacement
- changed devices still restart monitoring while idle; explicit stop/disable still ends a drag
- mouse movement maps to continuous dragged events while a drag is active
- two-finger expansion and contraction produce continuous native magnification values
- simultaneous two-finger contact can begin pinch without becoming an accidental click
- disabling or cancelling pinch safely ends the native magnification sequence
- disabling three-finger drag rejects the gesture and reports the reason
- adjustable thresholds and the left/right boundary are applied correctly
- finger movement or partial contact loss does not interrupt an active drag while another finger remains
- cancelling or disabling always releases an active drag
- finger movement, anchor movement, and replacement touches are rejected with a visible reason
- invalid gestures require a clean release before recognition resumes
- OS-version presets persist, follow the detected system version, and copy tuning after an OS change
- presets with removed drag choices migrate without losing their tuning or other OS presets
- the shared Hammerspoon-style transport observes motion at the HID tap and posts fresh dragged events at the session tap
- the modern drag source allows hardware mouse and keyboard events during synthetic dragging
- fresh dragged events leave the original motion unchanged and share a source with down/up
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

The application build compiles both Apple Silicon and Intel binaries, combines them into `build/MouseToucher 3.5.app`, embeds the generated `AppIcon.icns`, and applies an ad-hoc signature.

For macOS 27 Command Line Tools without Intel Swift compatibility libraries, build the local Apple Silicon app with `ARCHS=arm64 ./build.sh`. Verify the actual output with `lipo -info "build/MouseToucher 3.5.app/Contents/MacOS/MouseToucher 3.5"`. The included build uses arm64; universal compilation must be checked with a toolchain providing the Intel runtime libraries.

## Manual Magic Mouse checklist

- The menu-bar icon appears and the enable/disable control works.
- Choosing Restart from the menu closes the current process and launches one new MouseToucher process.
- Finder and Accessibility settings show the MouseToucher app icon rather than a generic application icon.
- The Settings window opens and changes are saved without rebuilding.
- The displayed current macOS version matches `sw_vers`, and its exact preset is marked as current.
- Adding an arbitrary past or future OS preset, marking it as default, and applying it to the current OS all work.
- There must be no drag-version selector or release-wait control. **ドラッグ入力** should show **macOS 27版・利用可能** after Accessibility permission is granted. The drag release condition should offer all-fingers-up, one-finger tap, and one-finger tap or anchor-plus-second-finger tap.
- Drag a Finder title bar and MouseToucher’s Settings title bar. Both must use ordinary synthetic drag input, with no direct Accessibility window-position path. Repeat with a file and text selection.
- Enter Mission Control, place the pointer over an app window preview, begin a three-finger drag, and move it to another Space in the top row. Note whether the preview follows the pointer and moves to the destination Space after lifting all fingers. Repeat with a physical mouse press as a control.
- Check ordinary file dragging, text selection, two-finger clicks, and pinch zoom.
- Change gesture settings or disable the app during a drag; the held button must release. If input monitoring cannot start, Settings must report it and no synthetic button-down should be sent.
- The live status updates touch count, gesture state, recognized operation, and cancellation reason.
- With the app running, put the Mac to sleep and wake it. After the Magic Mouse reconnects, verify touch count updates and taps, dragging, and pinch zoom work without restarting the app.
- Turn the Magic Mouse off and back on while the app stays open. Within a few seconds of reconnection, verify touch count and gestures work again. Repeat with the mouse disconnected when the app starts.
- Start a three-finger drag, then put the Mac to sleep. After wake, verify the old drag is released and the next gesture starts cleanly.
- In Safari or Preview, spreading two fingers zooms in smoothly and bringing them together zooms out smoothly.
- Pinching does not leak an ordinary scroll event into the target application.
- Releasing either pinch finger sends an ended phase and leaves the next tap responsive.
- The launch-at-login switch registers and unregisters the app on macOS 13 or later.
- A single finger resting, tapping, or scrolling does not click.
- Hold one finger still and tap the left half with a second finger: one left-click occurs.
- Hold one finger still and tap the right half with a second finger: one right-click occurs.
- Repeat the second-finger tap while keeping the anchor down: double-click and multi-click actions work.
- With the default release condition, place three fingers and move the mouse. Reduce to two and one finger: the item must still follow. Lift the final finger: the item must drop exactly once.
- Select one-finger tap release. Lift every finger, wait several seconds, then move again: the item must still follow. Briefly touch and release one finger to drop without an extra click.
- Select the combined release mode. Verify both a one-finger tap and the app's usual click gesture (rest one finger, tap with another) drop once without an extra click. A physical button press alone must not drop the item.
- Moving either finger during a two-finger click cancels only that click; the anchor can stay down for another attempt.
- Finger movement or partial contact loss after a three-finger drag begins does not release the dragged item while one finger remains.
- Stop mouse movement for at least 15 seconds while keeping three fingers in place, then move again. Record whether the item stays attached and whether the status says **ドラッグ中** or **ドロップ**. Lift all fingers and confirm the default mode drops; repeat in tap release mode to confirm it remains active until the tap.
- In a tap release mode, hold one finger longer than the tap threshold, move it beyond the movement tolerance, or add a second finger during its tap: none may drop the item. Lift all fingers, then make a fresh short single-finger tap to drop.
- Adding a third finger begins a drag when three-finger drag is enabled.
- Outside a latched drag, pressing the physical mouse button cancels touch recognition but still performs the normal physical click.
- Disabling compound tap prevents synthesized clicks immediately.
- Quitting and relaunching the installed application preserves Accessibility permission.

## Scope

Drag handling uses one macOS 27 Hammerspoon-style implementation for every target. It has no periodic event timer or direct window-position exception.

Automated tests do not post real click events or open multitouch devices. Device-refresh tests run the actual manager with a mocked framework boundary; no physical mouse is accessed. Those integrations depend on macOS Accessibility permission, the connected mouse, and Apple's private framework, so they are covered by the manual checklist above.

The event-shape tests do not prove that a real window moves. Complete the window and stationary-contact checks above after granting Accessibility permission to the newly named app.
