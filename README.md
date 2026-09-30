<p align="center">
  <img src="assets/app-icon-1024.png" width="88" height="88" alt="Tube Stash icon">
</p>

# Tube Stash

**Paste a YouTube link. Hit download. A playable MP4 lands in Downloads.**

By [Static Massive](https://staticmassive.com). No account. No cloud. No API keys. It only runs on your machine (`127.0.0.1`).

The download already includes Node, ffmpeg, and yt-dlp. You do **not** install anything else.

Use this for personal copies of videos you’re allowed to download. Respect YouTube’s terms and the creator’s rights.

<p align="center">
  <a href="https://github.com/StaticMassive/TubeStash/releases/latest/download/TubeStash-macOS.zip"><strong>Download for Mac</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/StaticMassive/TubeStash/releases/latest/download/TubeStash-windows.zip"><strong>Download for Windows</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/StaticMassive/TubeStash/releases/latest">Release notes</a>
</p>

## Download

| | File |
| --- | --- |
| **Mac** (Apple Silicon + Intel, macOS 11.3 or newer) | [TubeStash-macOS.zip](https://github.com/StaticMassive/TubeStash/releases/latest/download/TubeStash-macOS.zip) |
| **Windows** (64-bit) | [TubeStash-windows.zip](https://github.com/StaticMassive/TubeStash/releases/latest/download/TubeStash-windows.zip) |

## Mac

1. Unzip **TubeStash-macOS.zip**. Keep the whole **Tube Stash** folder together — don’t drag `Tube Stash.app` out by itself.
2. Right-click **Tube Stash.app** → **Open** → **Open** (macOS warns because it isn’t signed by Apple).

Tube Stash opens in its own window, like any Mac app — no browser. Quitting it stops everything it started. To keep it handy, right-click its Dock icon → **Options** → **Keep in Dock**.

Files land in `~/Downloads` as H.264 MP4 so QuickTime shows the picture, not a black screen with audio.

### If macOS blocks it

Right-click the app → Open. Or double-click **Fix macOS warning** in the unzipped folder.

## Windows

1. Unzip **TubeStash-windows.zip**. Keep the whole **Tube Stash** folder together.
2. Double-click **Open Tube Stash.bat**. Tube Stash opens in your browser.
3. If SmartScreen warns, click **More info** → **Run anyway**. Leave the black window open while you use it; close it to stop Tube Stash.

Files land in your **Downloads** folder.

## What it does

- Fetches title, thumbnail, duration, and available qualities
- Downloads video (H.264 MP4) or audio (M4A / MP3)
- Queue with live progress
- Playlists (this video vs whole list)
- Library of finished files — open, reveal, or hit × to delete (removes the file). Check several and **Delete selected**, or **Delete all**
- Queue — cancel, retry, or hit × to drop a row. Check several and **Delete selected**, or **Delete all**. × on a finished item also removes the file
- Nothing phones home. No sign-in.

## Develop

Your own copy can use Homebrew Node / ffmpeg / yt-dlp. The vendor folder is only inside the download zips.

```bash
npm install
npm start
# → http://127.0.0.1:47841
```

Rebuild the Mac app (needs Xcode or the Command Line Tools):

```bash
./scripts/build_app.sh
```

Build the Mac and Windows download zips:

```bash
./scripts/package.sh
```

## License

[MIT](LICENSE). Bundled Node, ffmpeg, and yt-dlp keep their own licenses (see `THIRD_PARTY.txt` inside the zip).
