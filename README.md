# Tidy

Native SwiftUI apps that keep your Mac and iPhone organized.

## Mac

| Section | What it does |
| --- | --- |
| **Overview** | The first screen. Explains each part of Tidy, shows what it found, and lists what Tidy has done. |
| **Downloads & Desktop** | Previews sorting loose files into `Screenshots`, `Images`, `Documents`, `Installers`, `Archives`, `Videos`, `Audio`, `Code` and `Other`. Exact duplicates (same SHA-256) go to the Trash. Flags files untouched for 90+ days. Nothing moves until you click **Tidy**, and **Undo** puts everything back. Optionally sorts **new downloads automatically** as soon as they finish, from the window or the menu bar. |
| **Apps** | Lists your apps by type, by size, or by those not opened in 6 months. Moves apps to the Trash, and moves apps sitting in Downloads or on the Desktop into Applications. Apps aren't rearranged inside Applications, because that can break updates. |
| **Clean Up** | Removes the items you tick: app caches, logs and Xcode and Simulator leftovers are deleted for good, and old installers go to the Trash. |
| **Storage** | Free-space bar, the size of every folder in your home folder, files over 200 MB, and known space hogs: old iPhone backups, Xcode files, app caches. |
| **Photos** | Screenshots, duplicates (same second and dimensions, with matching pixels) and longest videos. Right-click to preview a photo or play a video. Deletions go to Recently Deleted for 30 days, and reach your iPhone too if iCloud Photos is on. |
| **Tasks & Notes** | Simple to-dos with due dates, plus searchable notes. |

## iPhone

| Tab | What it does |
| --- | --- |
| **Photos** | The same cleanup as on the Mac: screenshots, duplicates and longest videos, plus how much space is free. Hold a photo to see it bigger or a video to watch it play. iOS asks before anything is deleted. |
| **Files** | Pick a messy folder in the Files app (for example Downloads in iCloud Drive, or On My iPhone). Tidy sorts it with the same rules as the Mac, with duplicates and Undo. It remembers the folder. |
| **Tasks** / **Notes** | To-dos and notes on the phone. |

Tasks and notes are stored separately on each device for now. Syncing them through iCloud needs a paid Apple Developer account.

## Build and run

Requires macOS 15+ and Xcode 16+.

**Mac app**

```bash
scripts/bundle.sh
open build/Tidy.app
```

For quick development builds, `swift build` works; `swift test` runs the tests. Photos and folder access only work from the bundled `.app`, because macOS reads the permission text from its `Info.plist`.

**iPhone app** (free Apple ID is enough)

1. Open `TidyiOS.xcodeproj` in Xcode.
2. Select the **TidyiOS** target › **Signing & Capabilities** › **Team** and choose your Apple ID (Personal Team). If the bundle ID is taken, change it to something unique.
3. Plug in your iPhone, choose it as the run destination, and press **Run**.
4. On the iPhone, trust the developer profile: **Settings › General › VPN & Device Management**. You may also need to turn on **Developer Mode** (Settings › Privacy & Security).

With a free account the app stops opening after 7 days. Press Run again in Xcode to refresh it.

## Project layout

| Folder | Contents |
| --- | --- |
| `Sources/Shared` | Code used by both apps: file sorting, photo scanning, task and note models |
| `Sources/Tidy` | Mac-only screens, Storage, the Downloads watcher and the menu bar item |
| `iOS` | iPhone-only screens |
| `Tests` | Tests for automatic Downloads sorting |

## Safety

- File moves are previewed first, and the last batch can be undone.
- Things are only ever moved to the Trash (or Recently Deleted), never deleted outright.
- Auto-sort only touches files that landed in Downloads *after* it started watching. It won't start until it can read the folder, and every sorted file has an **Undo** in the menu bar.
- Clean Up skips Apple's own caches and those of open apps, and shows what it will remove before anything happens.
- Storage won't trash anything inside `~/Library` or inside app or Photos library bundles. For those it only offers **Show in Finder**.

## Roadmap

- Sync Tasks & Notes between Mac and iPhone through iCloud (needs a paid Apple Developer account)
- Custom sorting rules
