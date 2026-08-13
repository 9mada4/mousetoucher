# MouseToucher workspace rules

## Automatic version naming

For every user-visible behavior change or newly distributed application build, automatically advance the current app version by `0.1` even when the user does not specify a version. For example, advance `1.5` to `1.6`. Do not bump the version for documentation-only or test-only edits that do not produce a new application build.

Unless the user explicitly requests a different version or says not to bump it, update all of the following together:

- the app bundle and executable name, such as `MouseToucher 1.6.app` and `MouseToucher 1.6`
- `CFBundleName`, `CFBundleDisplayName`, and `CFBundleShortVersionString`
- the version-specific bundle identifier, such as `com.mousetoucher.app.v1-6`
- `CFBundleVersion`, incremented by one
- every version or app-name string in `AppDelegate.swift`, `build.sh`, `README.md`, and `TESTING.md`

Apply the permission-cleanup workflow below for the previous version before building or launching the new version.

## App name, version, and Accessibility permissions

Whenever the app name, version-suffixed app name, executable name, or bundle identifier changes, treat the old and new builds as separate macOS applications.

Before building or launching the renamed app:

1. Record the old app name and old bundle identifier before editing them.
2. Stop the old app process.
3. Remove the old app bundle from both `build/` and `/Applications` when present.
4. Remove the old login item when present.
5. Reset permissions for the old bundle identifier with `tccutil reset All <old-bundle-id>`.
6. Verify that the old process and old app bundles are gone.
7. Build, sign, and launch the newly named app, then tell the user to grant Accessibility permission to the new app name.

Never run an unscoped global TCC reset. Always include the exact old bundle identifier, and always report whether the permission reset succeeded.
