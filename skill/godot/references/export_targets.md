# Export Targets

Use this reference only when the user asks to package, export, sign, or ship a Godot build.

## Cross-Platform Checklist

- Inspect `export_presets.cfg` first and reuse the preset names already in the project.
- Confirm that the installed Godot export templates match the local engine version before running CLI exports.
- Prefer debug exports first for device, browser, or desktop smoke tests; switch to release only after the build boots.
- Keep keystores, certificates, provisioning profiles, and passwords out of git unless the project already has an approved encrypted flow.
- Verify app name, bundle or package identifier, icon set, version, orientation, and feature-tag overrides per target before exporting.

## Android

- Requires the Android SDK, platform tools, build tools, and a supported JDK configured for Godot on the local machine.
- Release exports also need a signing keystore, alias, and passwords.
- The common artifact is an `.apk`; if the project already has an AAB or custom plugin flow, preserve it instead of replacing it.
- Treat debug exports as the first smoke-test step before generating a signed release artifact.

## iOS

- Treat iOS export as a macOS-only release path unless the project already has a verified remote-build setup.
- Requires Xcode plus Apple signing assets on the export machine.
- The Godot export is only part of the pipeline; finishing the build still goes through Xcode for signing, archiving, and App Store or TestFlight delivery.
- Confirm bundle identifier, team ID, capabilities, icons, and provisioning profile mapping before touching the preset.

## Web

- Reuse the existing Web preset and keep the generated HTML, JavaScript, WASM, and PCK files together when moving or deploying the build.
- Test Web exports over HTTP or HTTPS, never through `file://`.
- If the project uses threads or the browser shows a blank page, check COOP and COEP headers and the SharedArrayBuffer requirements for the hosting environment.
- Prefer single-threaded exports when Safari, iOS, or broader browser compatibility matters more than peak performance.

## Windows

- The common artifact is a `.exe`, sometimes accompanied by separate data files when the preset does not embed the pack.
- Preserve the project's existing signing flow if code signing is already part of release.
- Smoke test on a real Windows machine or VM when the build includes native extensions or platform-specific plugins.

## macOS

- Prefer exporting on macOS when shipping because signing and notarization are part of the real release path.
- The common distributable starts as an `.app`, often wrapped in `.zip` or `.dmg`.
- Confirm bundle identifier, entitlements, icon, hardened runtime, and notarization steps before calling the export complete.
- Treat non-macOS smoke exports as provisional until the app boots on macOS and passes signing and notarization.

## Feature Tags To Audit

- Mobile and desktop tags: `android`, `ios`, `mobile`, `windows`, `macos`, `pc`
- Web tags: `web`, `web_android`, `web_ios`
- Before changing platform-specific logic, search for `OS.has_feature`, feature overrides in `project.godot`, and preset-specific config in `export_presets.cfg`.
