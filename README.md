# Mouse Toucher

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="mousetoucher-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="mousetoucher-light.png">
  <img alt="Mouse Toucher Logo" src="mousetoucher-light.png">
</picture>

**Intentional tap-to-click and drag for your Apple Magic Mouse.** (v1.6)

Mouse Toucher adds a deliberate two-finger tap gesture to the Apple Magic Mouse. Keep one finger still as an anchor, then tap with another finger to click without pressing the mouse surface down. A single resting finger never clicks by itself.

## ✨ Features

- 🖱️ **Anchor + left-side tap** for left-click
- 🖱️ **Anchor + right-side tap** for right-click
- ⚡ **Repeat the tap** for double- and multi-click
- ✋ **Place three fingers** to start dragging immediately; lift all fingers to drop
- 🛡️ **Movement cancellation before a click** prevents scrolling and ordinary finger movement from becoming clicks
- 🎯 **Easy toggle** on/off from the menu bar
- ⚙️ **Live settings** for tap time, movement tolerance, left/right boundary, and three-finger drag
- 🧩 **macOS-version presets** automatically select the exact preset for the running OS
- 📊 **Live status** shows touch count, recognition state, last gesture, and cancellation reason
- 🚀 **Launch at login** can be controlled from the app on macOS 13 or later
- 🔒 **Privacy-focused** - runs entirely on your Mac, no network access

## 📋 Requirements

- macOS 11.0 (Big Sur) or later
- Apple Magic Mouse
- Your Magic Mouse must be connected via Bluetooth

## 🚀 Installation

### Option 1: Use Pre-Built Binary (Recommended)

A universal binary (works on both Apple Silicon and Intel Macs) is included in the `build` folder.

```bash
# Navigate to the repository
cd /path/to/mousetoucher

# Copy to Applications
cp -r "build/MouseToucher 1.6.app" /Applications/
```

### Option 2: Build From Source

If you prefer to build it yourself:

```bash
cd /path/to/mousetoucher
./build.sh   # Builds and ad-hoc codesigns the app so Accessibility permissions stick
cp -r "build/MouseToucher 1.6.app" /Applications/
```

### Grant Permissions

1. Open **MouseToucher 1.6** from your Applications folder
2. You'll see a permission request - click **"Open System Settings"**
3. In **Privacy & Security → Accessibility**, enable **MouseToucher 1.6** ✓
   - If the app is missing, click the **+** button and add it from `/Applications/MouseToucher 1.6.app`
4. Return to MouseToucher 1.6 – it will begin working automatically once the toggle is on (no relaunch needed)

That's it! You'll see a mouse icon in your menu bar.

## 📖 How to Use

### Basic Usage

1. Look for the **mouse icon** 🖱️ in your menu bar (top-right of screen)
2. Rest one finger on the mouse and keep it still
3. With another finger, make a quick tap
   - Tap the **left half** = normal click
   - Tap the **right half** = right-click (context menu)
4. Keep the anchor finger down and tap again for a double- or multi-click; the anchor does not need to be lifted between taps
5. To drag, place three fingers on the mouse, move the mouse immediately, then lift all fingers to drop
6. You can still press the mouse normally; physical clicks cancel any in-progress tap gesture

### Menu Bar Controls

Click the mouse icon in your menu bar to:

- **Enable/Disable** compound tap (checkmark shows when enabled)
- Open **Settings** to tune recognition and view live gesture status
- **View About** information
- **Quit** the app

### Settings and OS Presets

MouseToucher stores settings outside the version-specific app identifier, so they survive app updates. The settings window lets you:

- adjust tap duration, movement tolerance, and the left/right click boundary
- enable or disable three-finger drag
- see the current touch count, recognition state, last gesture, and cancellation reason
- add a preset for any past or future macOS version
- choose a default preset used as the template when an unregistered macOS version is detected
- copy any preset to the currently running macOS version for immediate use
- reset an individual preset to the initial values

At launch, MouseToucher reads the exact system version. If a matching preset exists it is applied automatically. After an OS upgrade or downgrade, a new exact-version preset is created from the selected default and then applied.

### Tips

- 💡 Keep the anchor finger still and make the second-finger tap **quick and light**
- 💡 During a three-finger drag, partial finger movement or contact loss will not interrupt it; lift every finger to drop
- 💡 The dividing line between left/right is roughly in the center of the mouse
- 💡 If a gesture is cancelled, lift all fingers once before starting again
- 💡 To disable temporarily, click the menu bar icon and toggle it off

## 🧪 Tests

The gesture recognizer and click-sequence logic have deterministic tests that run with Apple's Command Line Tools; a full Xcode installation is not required.

```bash
./run_tests.sh
```

## 🔧 Auto-Start on Login (Optional)

On macOS 13 or later:

1. Open **Settings** from the MouseToucher menu-bar icon
2. Turn on **Launch at login**
3. If macOS asks for approval, allow **MouseToucher 1.6** in **System Settings → General → Login Items**

The same switch removes the login item when turned off.

## ⚠️ Important Information

### About Private Frameworks

MouseToucher uses Apple's private **MultitouchSupport** framework to detect touches on your Magic Mouse. 

**What this means:**

- ✅ **Safe to use** - Many apps use this framework
- ✅ **Works great** on current macOS versions
- ❌ **Not on Mac App Store** - Apple doesn't allow private frameworks in the App Store
- ⚠️ **Future updates** - Could potentially break in a major macOS update (though unlikely based on history)

**Privacy:** The app only monitors your Magic Mouse touches. It doesn't collect data, access the internet, or send information anywhere.

### Accessibility Permissions

MouseToucher requires **Accessibility permissions** to:

1. **Detect** when you tap the Magic Mouse surface
2. **Send** click events to your Mac

These permissions are granted by you in System Settings and can be revoked at any time. The app cannot function without them.

## 🐛 Troubleshooting

### Taps aren't working

**Check permissions:**
1. Go to **System Settings → Privacy & Security → Accessibility**
2. Make sure **MouseToucher 1.6** is in the list and **checked** ✓
3. If it disappeared (after rebuilding), click **+** and re-add `/Applications/MouseToucher 1.6.app`
4. Toggle the checkbox off/on once — the app will detect the change immediately

**Verify Magic Mouse:**
1. Go to **System Settings → Bluetooth**
2. Your Magic Mouse should show as "Connected"
3. Try moving the mouse to confirm it's working

### App won't launch

**"App is damaged" error:**
- This is normal for apps not from the App Store
- Right-click MouseToucher 1.6 → **Open** → Click **Open** again in the dialog
- Or: Go to **System Settings → Privacy & Security** and click **Open Anyway**

### Adjusting sensitivity

If taps are too sensitive or not sensitive enough, open **Settings** from the menu-bar icon. Change the tap duration or movement tolerance and the active OS preset is saved and applied immediately.

## 🗑️ Uninstalling

To remove MouseToucher:

```bash
# Remove the app
trash "/Applications/MouseToucher 1.6.app"

# Remove from Login Items (if you added it)
# Or turn off Launch at login in MouseToucher Settings before removing the app

# Revoke permissions (optional)
# System Settings → Privacy & Security → Accessibility → Remove MouseToucher 1.6
```

## 💬 Feedback & Support

Having issues? Want to suggest a feature?

- **Check** the Troubleshooting section above
- **Open an issue** on GitHub if you find a bug
- **Contribute** submit a pull request
- **Share** with others who want tap-to-click for Magic Mouse!

## 🙏 Credits

This was 'vibe coded' using Claude Code (Sonnet 4.5)

Built to solve a frustrating gap in macOS - why doesn't the Magic Mouse have tap-to-click when the trackpad does?

Thanks to the reverse engineering community for documenting the MultitouchSupport framework, making apps like this possible.

---

**Enjoy your new tap-to-click Magic Mouse!** 🎉

*Made for Mac users who love the Magic Mouse but wish it had tap-to-click.*
