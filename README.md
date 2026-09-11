# 🎬 OBS Stream Highlight Marker

A lightweight, **zero-GPU / zero-RAM overhead** stream marker plugin for **OBS Studio**. 

Instead of running a heavy background replay buffer (like Medal or Shadowplay), this plugin timestamps clippable moments whenever you hit a hotkey while gaming. It syncs with your stream elapsed time, displays cards in an OBS dock panel, and exports formatted timestamps for your video editor or YouTube chapters.

---

## ⚡ Highlights

- **0% Extra GPU / RAM**: No replay buffer, no frame caching, no encoder lag.
- **Global In-Game Hotkey**: Works seamlessly while playing full-screen exclusive games.
- **Auto Broadcast Title**: Automatically detects YouTube/Twitch broadcast names from OBS.
- **Smart Pre-Roll**: Auto-calculates clip start & end windows (e.g. `[01:14:10 - 01:14:30]`).
- **Native OBS Dock**: Sits directly inside your OBS Studio layout with tags (`Clutch`, `Funny`, etc.) and editable notes.
- **Export Anywhere**: One-click export to `.txt`, YouTube Chapters, or DaVinci Resolve CSV.
- **Active Guard**: Prevents accidental hotkey triggers when you're not live or recording.

---

## 🚀 Quick Setup (3 Steps)

### 1. Add Script
In OBS &rarr; **Tools** &rarr; **Scripts** &rarr; click **`+`** &rarr; select `stream_marker.lua`.

### 2. Set Shortcut Key
In OBS &rarr; **Settings** &rarr; **Hotkeys** &rarr; search `Stream Marker: Mark Clip Point` &rarr; bind your key (e.g. `F8`).

### 3. Add Dock Panel
In OBS &rarr; **Docks** &rarr; **Custom Browser Docks...**:
- **Dock Name**: `Stream Markers`
- **URL**: `file:///YOUR_PATH_TO/highlightPlugin/dock/index.html`
- Click **Apply** and drag the dock into your OBS layout!

---

## 🎮 How It Works

```text
[Gaming Live] ──(Hit F8)──> [OBS Captures Timestamp] ──> [Live Dock Updates] ──> [Save .TXT / Chapters]
```

1. Start streaming or recording in OBS.
2. Whenever a clip-worthy moment happens, hit your shortcut key (e.g. `F8`).
3. The dock will chime, show your timestamp with lookback interval, and let you add quick tags or notes.
4. When finished, click **Save TXT** or **Copy All** for your video editor!

---

## 📄 Output Formats

| Format | Output Example | Best For |
| :--- | :--- | :--- |
| **Standard TXT** | `[00:14:12 - 00:14:32] (Elapsed: 00:14:32) [Clutch] 1v3 site hold` | Video Editors / Notepad |
| **YouTube Chapters** | `14:32 1v3 site hold` | YouTube Descriptions |
| **DaVinci Resolve** | `Blue,00:14:32:00,00:00:20:00,"Clutch","1v3 site hold"` | Direct Timeline Import |

---

## ⚙️ Configuration

In **Tools &rarr; Scripts &rarr; stream_marker.lua**:
- **Auto-detect Stream Title**: Automatically pulls broadcast title from YouTube/Twitch (`Default: ON`).
- **Lookback Pre-Roll**: Number of seconds before the keypress to set as the clip start (`Default: 20s`).
- **Output Folder**: Destination folder for saved `.txt` marker logs.

---

## 📜 License

MIT License © [Aischii](https://github.com/Aischii)
