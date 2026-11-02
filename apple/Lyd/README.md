# Lyd Apple Remote (Phase B)

SwiftUI multiplatform remote for **iPad**, **tvOS**, and iPhone (same target). Controls desktop Lyd over the LAN — **no audio streaming**.

Uses Phase A Windows API (`/api/v1`) from branch `cursor/phase-a-lan-remote-f144`.

## Open / generate

```bash
cd apple/Lyd
xcodegen generate
open Lyd.xcodeproj
```

Or open `Lyd.xcodeproj` directly after generation.

## Run against Windows Lyd

1. Start Lyd on the Windows host (API on port **8080** by default).
2. Prefer Bonjour: browse `_lyd._tcp` — instance looks like `Lyd-on-WS2026`.
3. If mDNS does not appear, use **Manual connection**:
   - Host: `192.168.44.154` (your LAN IP)
   - Port: `8080`
   - API root: `http://192.168.44.154:8080/api/v1`

Quick checks from the Mac:

```bash
curl -s http://192.168.44.154:8080/api/v1/health
curl -s http://192.168.44.154:8080/api/v1/library | head
dns-sd -B _lyd._tcp local.
```

## Simulator builds

```bash
# iPad
xcodebuild -project Lyd.xcodeproj -scheme Lyd \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -configuration Debug build

# tvOS
xcodebuild -project Lyd.xcodeproj -scheme Lyd \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -configuration Debug build
```

## Features

- Host picker for multiple `_lyd._tcp` servers + remember last host
- Manual IP:port fallback
- Library sync (songs / albums / covers) with revision polling (~4s)
- Playback: play, pause/playpause, next/prev, shuffle, seek, volume; state poll (~1s)
- Local Network usage string + Bonjour service `_lyd._tcp` in Info.plist

## Notes

- Trusted LAN only (no TLS/auth in this phase).
- Volume uses irrKlang scale `0.0…1.0`.
- JSON property names match Newtonsoft PascalCase from the Windows host.
