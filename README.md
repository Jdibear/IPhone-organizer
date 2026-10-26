# Tidy

A native SwiftUI Mac app that keeps your Mac (and, through iCloud, your iPhone) organized.

| Section | What it does |
| --- | --- |
| **Downloads & Desktop** | Previews sorting loose files into `Screenshots`, `Images`, `Documents`, `Installers`, `Archives`, `Videos`, `Audio`, `Code` and `Other`. Exact duplicates (same SHA-256) go to the Trash. Flags files untouched for 90+ days. Nothing moves until you click **Tidy**, and **Undo** puts everything back. |
| **Storage** | Free-space bar, the size of every folder in your home folder, files over 200 MB, and known space hogs: old iPhone backups, Xcode files, app caches. |
| **Photos** | Screenshots, likely duplicates (same second and dimensions) and longest videos. Deletions go to Recently Deleted for 30 days, and reach your iPhone too if iCloud Photos is on. |
| **Tasks & Notes** | Simple to-dos with due dates, plus searchable notes. Stored on this Mac for now. |

## Build and run

Requires macOS 15+ and Xcode 16+ (or the Swift toolchain).

```bash
scripts/bundle.sh
open build/Tidy.app
```

For quick development builds, `swift build` works. Photos and folder access only work from the bundled `.app`, because macOS reads the permission text from its `Info.plist`.

## Safety

- File moves are previewed first, and the last batch can be undone.
- Things are only ever moved to the Trash, never deleted outright.
- Storage won't trash anything inside `~/Library` or inside app or Photos library bundles. For those it only offers **Show in Finder**.

## Roadmap

- iPhone companion app, with Tasks & Notes synced through CloudKit (needs an Apple Developer account for the iCloud entitlement)
- Automatic tidying on a schedule, or whenever something lands in Downloads
- Custom sorting rules
