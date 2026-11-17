# Ninebot iOS Jailbreak Tweak — Design Brief (Research Only)

Date: 2026-11-17. Status: investigation only — **no tweak code has been written**.
Target device: jailbroken iPhone 14 Pro Max, iOS 16.4.1.
Goal: a tweak injected into the official iOS Ninebot app (九号出行), following the
approach of the Android project `wx9614-cell/NinebotEnhance` (an LSPosed module that
hooks the Android Ninebot app to cast content to the scooter dashboard and overlay
HUD information).

Sources (cloned shallow 2026-11-17, read locally; nothing downloaded, installed or run):
- `Xiaolangs/ninebot-cast-tweak` — iOS RE project for the official Ninebot app 6.10.9:
  Ghidra reports + Theos tweak sources. Main piece: `ProjectionOverride`.
- `wx9614-cell/NinebotEnhance` — Android LSPosed module for the Android Ninebot app
  6.10.10–6.10.12. Java/Kotlin, Gradle, builds an APK. Read for transferable ideas only.

---

## 1. iOS hook targets (exact class / method names)

Target app: **九号出行, Bundle ID `cn.ninebot.segway`, version 6.10.9** (arm64 thin binary,
205 MB; `REPORT_ninebot_ghidra.md:13-15`). The RE work was done against a decrypted copy
of this version; see §5 for the version-drift risk.

### 1.1 Primary intercept point — the encoder-input boundary

The official app does **not** mirror the phone screen. It renders its own navigation HUD
(turn arrow, distance, intersection zoom, traffic-light count, progress bar) per dashboard
model, converts the rendered `CGImage` to a `CVPixelBuffer`, and hands it to its own
H.264/MJPEG encoder (`REPORT_projection_navigation.md:11`, `tweak/README.md:§1`).

| Class | Selector | Address in 6.10.9 | Role |
|---|---|---|---|
| `NBPixelBufferConverter` | `-pixelBufferFromCGImage:` | `0x1010e0bfc` | App-rendered `CGImage` → `CVPixelBuffer` (32BGRA) into the encoder. **Main hook.** |
| `NBPixelBufferConverter` | `-pixelBufferFromCGImage_Mjpeg:` | `0x1010e0dd0` | MJPEG fallback path (BLE dashboards) |
| `NBVideoManager` | `-recordVideo:stopAfter:` | `0x1010e4d90` | Cast start — gate flag `casting=YES` |
| `NBVideoManager` | `-stop` | `0x1010e57ec` | Cast end — gate flag `casting=NO` |

Fallback if the frame does not go through the converter:
`-[NBVideoManager imageVideoEncoder:didEncodedImage:]` (post-encode; would need to produce
your own bitstream — harder, noted in `tweak/README.md:§1` and `tweak-theos/README.md:§8`).

How the existing dylib hooks them (two variants in the repo, same targets):
- `tweak/ProjectionOverride.m:101-163` — pure ObjC runtime, no Substrate: `method_setImplementation`
  via a `Swizzle()` helper (line 143), installed from a `__attribute__((constructor))` (line 153).
  Instance-method hooks only. `NBVideoManager` hooks gate a `g_casting` flag.
- `tweak-theos/Tweak.x:184-230` — Logos `%hook NBPixelBufferConverter` with **both** class (`+`)
  and instance (`-`) methods for both selectors, plus `%ctor` (line 565). Uses a bundled
  `substrate_shim.m` that implements `MSHookMessageEx` itself with `class_getInstanceMethod` +
  `method_setImplementation`, so the dylib is self-contained and has no Substrate/ElleKit
  dependency (`tweak-theos/README.md:§4`; shim at `tweak-theos/substrate_shim.m:11-17`).
  Note: `%hookf` (C-function hooking) is **not** available with the shim.

The hook replaces the **encoder input**, not the encoder: the replacement `CGImage` is passed
to the original implementation, so the app's own H.264/MJPEG encoding, RTP packetising, RTCP
heartbeat and UDP/KCP/BLE transport all continue unchanged (`tweak/ProjectionOverride.m:1-10`).
Frame size is taken from the incoming image at runtime — never hard-coded — so all dashboard
layouts (D1X/D2X/F43/2.4"/5") are handled automatically. A static frame is cached for 250 ms
(`FrameForSize`, `tweak/ProjectionOverride.m:88-99`); the callback runs on the cast thread at
25 fps, so drawing must stay cheap and must not block (heartbeat loss stops the cast).

Runtime toggles (all via `NSUserDefaults`, no UI):
`NBProjectionOverride` (default YES — set NO to restore the native frame),
`POOrientation` (0/90/180/270, default 90), `POScaleMode` (`fit` default / `fill`),
`POMirror`, `POFrameDump` (dumps first 5 frames to `Documents/POFrames/cast_*.png`)
(`tweak-theos/Tweak.x:31,41,118,157,569`).

### 1.2 Secondary hook surfaces found in the same repo

- `NavigationViewBuilder buildView(_:fatherView:userImage:)` @ `0x1010a3260` — the per-model HUD
  view builder (Swift; hook by mangled name or base+offset). This is the "keep the app layout,
  change one element" layer, as opposed to the whole-frame replacement above
  (`tweak/README.md:§6`, `REPORT_projection_navigation.md:§2`).
- HUD data model `NavigationInfoModel` fields: `iconType`, `crossImage` / `turnIconImage`,
  `gpsSignal`, `index`, `routeTrafficLightCount`, `roadLine`, `speed`
  (`REPORT_projection_navigation.md:§2`). Reusing these lets a tweak overlay real nav data
  instead of drawing static content.
- Per-model layout views: `D1XTurnInfoView`, `D1X1TurnInfoView`, `D2XCombinedInfoView`,
  `F43TurnInfoView`/`F43CombinedInfoView`, `TwoFourInchesTurnInfoView` (2.4"),
  `FiveInchesTurnView` (5"); components `CombinedTurnInfoView`, `CombinedDistanceInfoView`,
  `NavigationProgressBarView`, `D2XProgressView`, `TrafficStatusBar`, `RoadLineSeperateView`,
  `CombinedMapInfoView`, `BackgroundInfoView`, `EasterEggsView`.
- Diagnostic probes (separate small dylibs, each its own `tweak-*/` dir, all built by the same
  CI workflow): `tweak-net` (NetPlainLog — plaintext interface logging), `tweak-key` /
  `tweak-seed` / `tweak-keybody` / `tweak-nbkey` (key capture), `tweak-theme` / `tweak-themeapply` /
  `tweak-themepush` (theme/skin probes and push), `tweak-fw` (firmware probe), `tweak-body`
  (request plaintext), `tweak-peek` (read-only cache values), `tweak-cccrypt` (CCCrypt interpose),
  `tweak-debug` (opens the app's built-in debug tools from the home page), `tweak-cmddump`
  (command set from the DynamicTool singleton), `tweak-agshim` (fixes App Group / Keychain /
  UserDefaults after re-signing), `tweak-noyidun` (forces the Yidun encryption switch off).
- Network/decrypt logging inside `tweak-theos/Tweak.x:482-563`: `%hook NSURLSession`
  (`dataTaskWithURL:` / `dataTaskWithRequest:` / `downloadTask…`), `%hook JCOREDataSecurity`
  (AES256/SM4 decrypt variants), `%hook JCOREUtilities`, `%hook JCORESm4Crypt`,
  `%hook NSJSONSerialization` (request/response JSON, capped at 400 entries).
- Sim preview (no dashboard needed): a floating "模拟投屏" button + a tap gesture on the
  "拥有爱车" label opens a fullscreen preview that renders the replacement frame at 25 fps
  (`tweak-theos/Tweak.x:239-480`). Useful for testing drawing without a vehicle.

### 1.3 What the Theos project does NOT contain

There is **no filter plist** in `tweak-theos/` (directory contains only `Makefile`, `control`,
`Tweak.x`, `substrate_shim.m`, `include/`, `README.md`). The project is built for **sideload
injection** (dylib added via `LC_LOAD_DYLIB`, same-certificate re-sign — see §4.3), not for
Substrate/ElleKit injection on a jailbroken device. For a jailbreak install, a filter plist
(e.g. `Filter: Bundles: [cn.ninebot.segway]`) and `.deb` packaging (`make package`) would have
to be added; the `control` file (`tweak-theos/control`) already carries the Debian metadata
(`Package: com.rev.projectionoverride`, `Version: 1.0.0`, `Architecture: iphoneos-arm64`).

---

## 2. How the official iOS app builds and sends the cast frame

Per `REPORT_projection_navigation.md` (all addresses are for 6.10.9):

1. **Orchestration** — `Vehicle.NBProjectionScreenManager` (Swift): `setupResources(with: ConfigModel)`
   @ `0x101e77b94` starts the session once the dashboard sends its `ConfigModel`;
   `releaseResources()` @ `0x101e77d10` stops it. It holds `videoGenerator` and
   `videoUdpController`. Delegate callbacks gate sending and quality:
   `videoGenerator:shouldSendRTPData:` / `shouldSendRTCPData:` / `didRecievedHeartBeat:` /
   `rtcpMeesageOnError:` / `modeChanged:`.
2. **Rendering** — `NBVideoFactoryModule` (759 functions): `NavigationViewBuilder` builds a
   per-model HUD `UIView` (`buildView(_:fatherView:userImage:)` @ `0x1010a3260`) from
   `NavigationInfoModel`. The app renders that view to a `CGImage` each frame.
3. **Encoding** — `VideoGenerator` (`startRecordVideo` @ `0x1010c9268`, `stopRecordVideo`,
   `suspendRecordVideo`, `buildMapView`, `createStartHeartBeatCommand`, `handleRTCP`,
   `videoBufferShouldSend`, `rtcpBufferShouldSend`) + `NBVideoManager`. Default config
   (`NBVideoConfiguration.defaultConfiguration` @ `0x1010e4a10`, values **inferred** from
   inline constants): **25 fps, 500,000 bps, 240×320** frame, 1400-byte RTP packets,
   GOP 10, max 2 B-frames. The dashboard can override via `ConfigModel` (`videoSize` /
   `targetSize` / `scaleSize` / `scale` / `codecType` / `maxBFrame` / `frameRate` / `bitRate` /
   `gopSize` / `layout` / `hearBeat` / `compressType` / `rtcpChannel` / `production`).
4. **Transport (UDP/RTP)** — `VideoUDPController.rtpPort = 5012`, `rtcpPort = 5013`
   (`0x101063a68`/`0x101063a70`). KCP reliable layer available (`KCPClient`/`KCPServer`,
   `connect` @ `0x10108f57c`, `send` @ `0x101090100`). RTP framing:
   `NBRTPHandler::createRTPBufferFrom:withPayload:RTPStandard:isFirst:isEnd:` @ `0x1010e2a64`;
   `isEnd` sets the marker bit; `RTPStandard == 2` is the video class with an extension header.
5. **Transport (BLE)** — `NBBleSdk::BleManager::sendRtcpData` @ `0x10097c288` (+ `sendRtpData`,
   `registerRtcpNotification`); `NBBluetoothModule::BleRTCPDataSend` / `BleRTPDataSend`.
6. **Control plane (RTCP APP)** — `NBRTCPHandler::createAppCommandBy:withValues:` @ `0x1010e15c0`.
   Heartbeat: `VideoGenerator::createStartHeartBeatCommand()` @ `0x1010ca59c` =
   `createAppCommandBy:` **5** `withValues:` **[0, 2]**; there is a `maxHeartBeatLostTimes` limit.
   Only command 5 is confirmed; command 6 is related to BYE.
7. **Capability split (inferred, not proven)** — the binary contains both `支持简易导航` and
   `支持投屏导航` markers; the report infers low-end dashboards get "simple navigation"
   (plain-text turn-by-turn over BLE/RTCP) and high-end ones get the HUD video stream over
   UDP/KCP 5012, decided by firmware capability bits. Not verified in code.

Note: the app's own cast is a **navigation HUD video stream**, not a screen mirror — it only
runs during navigation cast, and only the HUD it renders is sent. A tweak that wants to show
arbitrary phone content (e.g. another app's screen) would have to render that content into the
replacement `CGImage` itself (e.g. by snapshotting a `UIView`/screen, or running its own
capture) — the app provides no screen-capture source.

---

## 3. What is transferable from NinebotEnhance (Android) — in principle only

NinebotEnhance is an LSPosed module for the **Android** Ninebot app (`cn.ninebot.ninebot`,
6.10.10–6.10.12). Nothing in it is portable as code (Java/Kotlin, LSPosed, Android
MediaProjection/VirtualDisplay/Shizuku have no iOS equivalents). What transfers is the
**design and the protocol/data facts**:

### 3.1 The same interception pattern, independently arrived at

- Android side: Ninebot's own encoder calls into the module to obtain the frame —
  `FrameClient.replace(Bitmap original)` / `replacement(width, height, density, early)` and
  `draw(Canvas, width, height)` (`FrameClient.java:1054-1113`). The module composites its
  picture + HUD into one bitmap and hands it back; Ninebot's own encoder/sender does the rest.
  This is the exact analogue of the iOS `NBPixelBufferConverter` hook (§1.1): **intercept at
  the encoder-input boundary inside the host app, reuse the app's encoder and transport.**
- Frame production (Android): `ImageReader` from a VirtualDisplay or MediaProjection, read at
  20 fps (`FramePacer.TARGET_FPS = 20`, 50 ms pacing, `acquireLatestImage`, coalesced callbacks
  — `FrameClient.java:602-643`); composed/scaled to the dashboard frame size with
  `Geometry.fit`; a `pictureRevision` counter deduplicates identical frames.
- Frame size: dashboard reference **848×480** (5-inch; `DashboardProfile` per vehicle);
  half-screen vertical dash is **240×320**. Encoder override range 100 kbps–3 Mbps, 5–30 fps.
  M5P dash config: Wi-Fi Direct, H.264, 1.5 Mbps, 20 fps. Android encoder path:
  `CodecCaptureController` → FFmpeg `h264_mediacodec` (`CODEC_H264_GPU`).

### 3.2 HUD overlay design (geometry, directly reusable)

`DashboardHud` draws at 848×480 reference coordinates (`docs/architecture.md`):
- Right column x 648–838, left column x 443–633; cards stacked bottom-up, 6 px gaps.
- Cards: phone status (28 px high), music (84 px with track, hidden when idle, auto-hide
  3–15 s after track/play-state change), tyre pressure (28 px), voltage (28 px, or 84 px with
  a 10–60 s voltage chart), speed/power cards (same size as voltage, default off).
- Notifications: bottom-right (right=838, bottom=468), 1–5 shown (default 3), 440 ms slide-in.
- Volume bar: bottom-left (14,150)–(46,376).
- **Occlusion zone (640,44)–(842,254)**: the dashboard's own gauge card is painted over the
  frame there — HUD cards must avoid it (cards that extend into it are pushed to the left column).
- Conditions per card: always / on-change (show N seconds after an event) / when-in-range
  (speed, power, voltage, volume, tyre pressure/temp intervals, or "playing").

### 3.3 Vehicle-data sources (concepts + register facts)

- Android reads vehicle telemetry by observing Ninebot's own BLE reply path
  (`DynamicDevice.onResponse(NbFrame)`) and by reusing Ninebot's own
  `DynamicDevice.sendCommand(name, null, addToFirst=true, timeoutRetry=0, callback)`.
  The iOS equivalent would be finding the iOS app's BLE reply path (likely inside
  `NBBluetoothModule`, 646 functions per the Ghidra module map) — **not yet located**.
- Register facts worth reusing: tyre pressure frame — register 1 low byte = rear pressure,
  high byte = front pressure, register 2 same order for temperature; pressure × 0.02,
  temperature − 40. Voltage registers are 10 mV little-endian. `rVoltage` / `rVoltage2` /
  `rVoltage3`, `rVrlaVoltage` (measured bus voltage), `rBool` bit 0 = power-on state.
  Tyre pressure polled every 30 s, voltage every 1 s; reads only while a cast/virtual-display
  session runs and only for enabled cards; no write commands are ever sent.
- Speed/power (`rSpeed` in 0.1 km/h, `rPower` signed 16-bit, negative = regen) come from the
  vehicle itself, never from BMS.

### 3.4 Navigation data onto the dash (the most valuable transferable idea)

- Android: Amap's `curManeuverID` maps **directly** onto Ninebot's NaviState numbers
  (`AmapNavi.parse`). The module writes TFT-board command **113** via Ninebot's own
  `sendCommand`: `setNaviDistance` (int32 total metres), `setNaviRoad` (UTF-8 + NUL),
  `setNaviRoadNext`, `setNaviInfo` (18 bytes: int32 remain m, int32 remain s, int16 icon,
  int32 current-segment remain m, int16 traffic-light count, int16 GPS level),
  `setNaviDriveInfo` (int32 driven m, int32 used s). `setNaviStart 3` is sent by Ninebot's
  own cruise page, not by the module. Sent once per second, only during a cast session.
- On iOS this would mean: get turn data from an iOS navigation source (Amap iOS SDK, or
  `MapKit`/`CoreLocation` guidance) and write the same command 113 through the iOS app's
  own command path — **the iOS-side command-sending function is not yet identified** in the
  RE material (the Android `sendCommand` equivalent on iOS is an open unknown, §5).
- Alternative without any command writing: render the turn arrow + distance + road name
  **into the replacement frame** at the `NBPixelBufferConverter` hook (§1.1). This is simpler
  and is the natural first step: the iOS app already renders its own nav HUD there, so a
  tweak can draw its own arrow/text over or instead of it.

### 3.5 Not transferable (Android-only)

LSPosed/Xposed hooking, VirtualDisplay + Root/Shizuku/Sui, MediaProjection screen capture,
`NotificationListenerService`, `MediaSessionManager`, BMS-over-BLE via Android GATT
(DL/ANT/JBD/JK protocols — the *protocols* are documented in `core/` and could be re-read,
but the GATT plumbing is Android), headlight control via Android BLE, USB/Bluetooth
touch panels, APK signing/LSPosed scope. The Android module also hooks the navigation apps
themselves (Amap/Tencent/Baidu) — on iOS, navigation apps are separate sandboxed processes
and cannot be hooked the same way; nav data must come from an SDK or from iOS location APIs
inside the Ninebot app process.

---

## 4. Minimal first tweak — proposed design

### 4.1 v0.1: whole-frame HUD overlay at the converter hook (smallest useful step)

- Fork the proven `ProjectionOverride` pattern: hook `NBPixelBufferConverter
  -pixelBufferFromCGImage:` (+ the `_Mjpeg:` variant) and gate on `NBVideoManager
  -recordVideo:stopAfter:` / `-stop`, exactly as in `tweak/ProjectionOverride.m`.
- Instead of replacing the frame entirely, **composite**: call the original implementation's
  input image, draw the app's frame into a bitmap context, overlay custom HUD text/graphics
  on top (e.g. live speed from `NavigationInfoModel.speed`, a custom turn arrow, phone
  battery/time), and pass the composited image to the original converter. This keeps the
  app's own nav HUD and only adds information — lower risk than full replacement, and it
  reuses the app's own data model.
- Keep the existing safety properties: size from the incoming image, 250 ms frame cache,
  `NBProjectionOverride` kill-switch, `POOrientation`/`POScaleMode` handling, os_log
  diagnostics, `POFrameDump` for verifying what actually reaches the encoder.
- Deliverable: one `.dylib` (+ `.deb` for jailbreak install, see §4.3).

### 4.2 v0.2 candidates (in order of increasing difficulty)

1. **Real vehicle data overlay** — locate the iOS BLE reply path (`NBBluetoothModule`) and
   read speed/power/voltage/tyre pressure the way NinebotEnhance does on Android (§3.3);
   overlay the values using the §3.2 geometry (right column, avoid the (640,44)–(842,254)
   occlusion zone on 848×480).
2. **Navigation arrows from phone nav** — obtain turn data (Amap iOS SDK or MapKit) inside
   the tweak and draw arrow + remaining distance/road name into the frame (§3.4, draw-only
   variant — no command 113 writing).
3. **Command 113 writing** — find the iOS `sendCommand` equivalent and write nav data to the
   dash the way NinebotEnhance does; only after v0.2/1 works.
4. **Screen content** — render arbitrary phone content into the frame (snapshot a view, or a
   ReplayKit-style capture inside the app process). Hardest; the app's cast pipeline is a
   25 fps HUD renderer, not a screen mirror.

### 4.3 Build and install (jailbroken device)

- **Build** — reuse the proven CI pattern in
  `ninebot-cast-tweak/.github/workflows/build-dylib.yml` (two jobs worth copying):
  - *Theos (Logos)*: `macos-14` runner, clone Theos `--recursive` (cached), install `ldid`
    via Homebrew, `make` in the tweak dir. Makefile essentials
    (`tweak-theos/Makefile:1-9`): `TARGET = iphone:clang:latest:13.0`, `ARCHS = arm64`,
    frameworks `Foundation CoreGraphics CoreVideo CoreText ImageIO UIKit`,
    `-install_name @executable_path/ProjectionOverride.dylib`. Verification step asserts
    arm64, the install name, and that `_MSHookMessageEx` is defined in the dylib with no
    remaining substrate undefined symbols.
  - *Plain clang* (fallback, no Theos): `xcrun --sdk iphoneos clang -arch arm64
    -miphoneos-version-min=13.0 -dynamiclib` on the `.m` file — this is the variant that
    needs no Logos at all.
  - The same workflow builds all the probe dylibs; a new tweak should be added as another
    job or by extending the `paths:` trigger list.
  - The user has no Mac; GitHub Actions on a macOS runner is the build path (same as the
    existing Ninebot Pro+ IPA workflow). `ldid` pseudo-signing is enough for the dylib
    artifact; the final install signing happens on-device / at packaging time.
- **Install on the jailbroken phone** — two routes:
  - *Jailbreak-native (preferred for this user)*: package as a `.deb` (`make package`,
    add the missing filter plist `Filter: Bundles: [cn.ninebot.segway]` and a
    `postinst` that resprings/restarts the app), install via Sileo/Zebra or `dpkg -i`.
    Injection is then done by ElleKit/Substrate, so the `substrate_shim.m` is unnecessary —
    the Logos `%hook` calls resolve against the real `MSHookMessageEx`. (The shim is only
    needed for the sideload route.)
  - *Sideload (already proven by the repo)*: inject the dylib into a decrypted Ninebot IPA
    with `optool` (`LC_LOAD_DYLIB`), re-sign dylib + app with the **same** certificate, keep
    the original entitlements. Needs a decrypted IPA (jailbroken device can dump it on-device).
    The repo's `SIGNING.md` documents lessons from its own sideload setup: its signing
    material was tied to a single other person's ad-hoc profile with a non-wildcard App ID,
    which forced a bundle-ID change — with login/push consequences. **Do not reuse that
    material; the user must sign with their own certificate/profile.** (No signing values are
    reproduced in this brief.)
- **Runtime requirements**: the official Ninebot app installed; a dashboard in cast-receive
  mode; the tweak loads into the app process at launch. Settings via `NSUserDefaults` keys
  (no preference UI in v0.1; a `PreferenceLoader` pane can come later).

---

## 5. Open unknowns and risks

1. **App version drift (biggest risk).** All RE is for **6.10.9**. The App Store is likely on a
   newer version; class/method names may have changed. Mitigation: the hooks use class +
   selector names, not addresses, so they survive minor updates — but if `NBPixelBufferConverter`
   or `NBVideoManager` was renamed/restructured, the tweak silently does nothing (it logs
   "class not found" / "selector not found" via os_log). First step on-device: install a
   logging-only build and check `log stream` for the hook lines.
2. **Which Ninebot app version is actually on the phone, and is it decrypted?** A jailbroken
   device can dump the decrypted binary on-device (e.g. frida-ios-dump / bfdecrypt-style
   tools), but that step has not been done. The tweak itself does not need the binary — only
   the class/selector names — but verifying them against the installed version needs either
   the decrypted binary or runtime class-dump on device.
3. **Does the cast really go through `pixelBufferFromCGImage:` on the user's dashboard?**
   The repo notes this is not yet proven at runtime for every model; the MJPEG branch is
   hooked as a backup, and the post-encode fallback (`imageVideoEncoder:didEncodedImage:`)
   is unimplemented. The `POFrameDump` toggle exists precisely to verify what reaches the
   encoder.
4. **Anti-tamper / jailbreak detection.** The 6.10.9 binary contains `jailbreak`/`cydia`/
   `frida`/`ptrace` strings, but no detection function was located and it is unconfirmed
   whether casting is gated on it (`tweak/README.md:§5.7`). Risk: the app may refuse to run,
   log in, or cast on a jailbroken device, or after injection. Test with the logging-only
   build first; if the app exits abnormally, this is the first suspect.
5. **iOS-side command path for nav data (command 113) is unidentified.** The Android
   `DynamicDevice.sendCommand` equivalent on iOS has not been found in the RE material.
   The draw-only nav overlay (§4.2.2) avoids this entirely.
6. **iOS-side vehicle telemetry source is unidentified.** `NBBluetoothModule` (646 functions)
   is the likely home of the BLE reply path, but no specific class/method has been pinned
   down. The v0.1 overlay must therefore use data already in the frame (`NavigationInfoModel`)
   or phone-side data (battery, time), not live vehicle telemetry.
7. **Hook stability / threading.** The converter callback runs on the cast thread at 25 fps;
   drawing must be fast, cached, and lock-protected. Blocking the hook stalls the heartbeat
   and the app stops the cast. The existing 250 ms cache + lock pattern should be kept.
8. **No filter plist / no .deb in the reference project.** Jailbreak packaging has to be
   created from scratch (§1.3). Also note the reference Makefile targets iOS 13.0 minimum
   (`TARGET = iphone:clang:latest:13.0`) — fine for a 16.4.1 device, but the SDK on the
   Actions runner will be newer; verify the dylib still loads (it only needs ObjC runtime +
   CoreGraphics, no new APIs).
9. **ElleKit vs Substrate.** Modern Dopamine uses ElleKit, which provides `MSHookMessageEx`
   with the same signature the Logos output expects, so the Theos build should work as-is on
   the jailbroken device. The bundled `substrate_shim.m` must **not** be linked in the
   jailbreak build (it would define a duplicate symbol); keep it only for the sideload variant.
10. **Legal / ToS.** The tweak hooks a third-party app's binary and modifies its behaviour.
    It is for the user's own device and their own scooter. Do not redistribute the patched
    Ninebot app or the decrypted binary.

---

## 6. Suggested order of work

1. On-device recon (logging-only dylib): confirm the installed Ninebot version, that
   `NBPixelBufferConverter` / `NBVideoManager` exist with those selectors, and that frames
   flow through the hook during a real cast (os_log `[CAST] frame #…`).
2. v0.1 overlay tweak (§4.1) built via GitHub Actions, packaged as `.deb`, installed on the
   jailbroken phone; verify with `POFrameDump` frames + dashboard photo.
3. Locate the iOS BLE reply path for live telemetry (v0.2.1); locate the iOS command-send
   path for nav data (v0.2.3).
4. Preference UI (on/off, orientation, overlay content toggles) only after the core hook is
   proven on-device.
