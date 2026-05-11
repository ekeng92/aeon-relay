# Feature: Installation Scripts

## Purpose
Three scripts for installing, remote-installing, and uninstalling AEON Relay on macOS.

## Scripts

### install.sh (local)
1. Check macOS version (13+)
2. Check Swift toolchain
3. Create `~/.aeon-relay/` directory structure
4. Build via `make app`
5. Kill running instance
6. Copy to `~/Applications/`
7. Codesign (ad-hoc)
8. Launch

### remote-install.sh
1. Check macOS and Swift prerequisites
2. `git clone --depth 1` to temp dir
3. Run `install.sh`
4. Clean up temp dir
5. Supports `--uninstall` flag to download and run uninstall.sh

### uninstall.sh
1. Kill running instance
2. Remove `~/Applications/AEON Relay.app`
3. Remove `~/.aeon-relay/`

### Makefile
- `build` - swift build release
- `app` - build + create app bundle with Info.plist, codesign, stamp BuildInfo.swift
- `run` - build + open
- `install` - build + copy to ~/Applications + open
- `uninstall` - kill + remove app + remove config
- `clean` - swift package clean
- `test` - swift test

## Known Limitations
- `remote-install.sh` clones to `$TMPDIR/aeon-relay-install` which could conflict if multiple installs run simultaneously
- `install.sh` uses `AEON_PREFIX` env var for custom home (undocumented)
- No version pinning on remote install (always gets HEAD)
- `make app` stamps BuildInfo.swift then restores it, which could leave it dirty if the build fails mid-way
- No LaunchAgent setup (app doesn't auto-start on login)
- Codesign is ad-hoc (`--sign -`), which means Gatekeeper may block the app
- Uninstall removes ALL config including audit logs (no option to preserve)

## Test Coverage
**None.** Scripts are not tested.
