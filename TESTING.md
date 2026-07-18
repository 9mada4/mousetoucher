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
- the same anchor can be reused for consecutive clicks
- slow taps, finger movement, anchor movement, replacement touches, and a third finger are rejected
- invalid gestures require a clean release before recognition resumes
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

The application build compiles both Apple Silicon and Intel binaries, combines them into `build/MouseToucher.app`, and applies an ad-hoc signature.

## Manual Magic Mouse checklist

- The menu-bar icon appears and the enable/disable control works.
- A single finger resting, tapping, or scrolling does not click.
- Hold one finger still and tap the left half with a second finger: one left-click occurs.
- Hold one finger still and tap the right half with a second finger: one right-click occurs.
- Repeat the second-finger tap while keeping the anchor down: double-click and multi-click actions work.
- Moving either finger beyond the threshold cancels the gesture.
- Adding a third finger cancels the gesture.
- Pressing the physical mouse button cancels the gesture but still performs the normal physical click.
- Disabling compound tap prevents synthesized clicks immediately.
- Quitting and relaunching the installed application preserves Accessibility permission.

## Scope

Automated tests do not post real click events or connect to MultitouchSupport. Those integrations depend on macOS Accessibility permission, the connected mouse, and Apple's private framework, so they are covered by the manual checklist above.
