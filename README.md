# 🎬 OBS Stream Highlight Marker Plugin

A zero-GPU, zero-RAM overhead stream marker tool for **OBS Studio**. 

Instead of burning CPU/GPU resources and memory on a continuous replay buffer (like Medal or Shadowplay), this plugin simply timestamps clippable stream moments whenever you hit your shortcut key while gaming. It tracks stream elapsed time, displays markers on an OBS dock panel, and exports them directly to a `.txt` file with your stream title.

---

## ✨ Features

- **🎯 Auto Stream Title Detection**: Automatically detects your live stream broadcast title from OBS (YouTube Broadcasts, Twitch Stream Info) so you never have to re-type it every session!
- **⚡ Zero Performance Overhead**: No video rendering, no encoder load, and no RAM caching. Perfect for high-refresh-rate gaming and budget/single-PC streaming setups.
- **🌐 Global In-Game Hotkey**: Uses OBS's native hotkey engine—triggers reliably even inside full-screen exclusive games.
- **🕒 Smart Lookback Pre-Roll**: Automatically calculates both the clip start point and end point (e.g., `[01:14:10 - 01:14:30]`) so your video editor knows the exact clip window.
- **📊 Native OBS Dock Panel**: Sits seamlessly inside OBS Studio alongside your chat, scenes, and audio mixer.
- **🏷️ Quick Tagging & Notes**: Categorize moments with tags (`Clutch`, `Funny`, `Kill`, `Fail`, `Star`) and type notes inline.
- **🔔 Pleasant Audio Chime**: Subtle audio feedback confirms when a marker is registered (can be toggled on/off).
- **💾 Multi-Format Export**:
  - **Standard `.txt`**: Formatted with stream title, date, clip range, and notes.
  - **YouTube Chapters**: Ready to paste into your YouTube video description.
  - **DaVinci Resolve Marker CSV**: Importable directly onto the editing timeline.
  - **Adobe Premiere Pro EDL**: Direct marker import.
  - **One-Click Clipboard**: Instant copy for Discord or notepad.

---

## 🚀 Setup Guide (2 Minutes)

### Step 1: Add the Lua Script to OBS
1. Open **OBS Studio**.
2. Click **Tools** in the top menu &rarr; **Scripts**.
3. In the Scripts window, click the **`+`** (Add) button at the bottom left.
4. Navigate to this folder and select `stream_marker.lua`.
5. You will see the script settings appear:
   - **Stream Title / Game**: Name of your stream (can also be edited in the dock).
   - **Lookback Pre-Roll (Seconds)**: Default `20` seconds (how far back from the keypress the clip starts).
   - **Output Folder**: Choose where you want `.txt` files saved (defaults to this folder).
6. Click **Close**.

---

### Step 2: Set Your Global Shortcut Key
1. In OBS, go to **Settings** &rarr; **Hotkeys**.
2. In the filter search bar at the top, type `Stream Marker`.
3. Locate **Stream Marker: Mark Clip Point**.
4. Bind your preferred shortcut (e.g., `F8`, `Page Down`, or a Stream Deck / mouse button).
5. Click **Apply** &rarr; **OK**.

> *Note: This hotkey works globally while you are playing your game in full-screen.*

---

### Step 3: Add the Live Panel to OBS
1. In OBS, click **Docks** in the top menu &rarr; **Custom Browser Docks...**
2. In the **Dock Name** column, enter: `Stream Markers`
3. In the **URL** column, enter the absolute path to `dock/index.html`:
   ```
   file:///c:/Users/Ais-PC/highlightPlugin/dock/index.html
   ```
4. Click **Apply**.
5. The **Stream Markers** panel will open! You can now drag and dock it anywhere in OBS (next to Chat, Scenes, or Controls).

---

## 🎮 How to Use During a Stream

1. **Start Streaming**: When you click *Start Streaming* in OBS, the panel will turn **LIVE** and start the stream clock.
2. **Hit Your Hotkey**: Whenever something awesome happens in-game, hit your shortcut.
3. **Check the Panel**: A new marker card instantly pops up showing:
   - Stream timestamp (e.g., `01:23:45`)
   - Pre-roll interval (e.g., `01:23:25 - 01:23:45 (20s)`)
   - Wall clock time
4. **Add Context (Optional)**: Click a tag chip (`🔥 Clutch`, `😂 Funny`) or type a quick note into the card.
5. **Save & Export**:
   - Click **Save TXT** to download `<Stream_Title>_<Date>_markers.txt`.
   - Click **Copy All** to paste all marks into Discord or a notepad.
   - Click **Formats ▾** to export as YouTube Chapters or DaVinci Resolve markers.

---

## 📁 Sample Text Export

```text
================================================================
STREAM HIGHLIGHT MARKERS: Valorant Ranked Grind
Date: 2026-09-11 21:30:00
Format: [Clip Range] (Elapsed) - Tag: Note
================================================================

[00:14:12 - 00:14:32] (Elapsed: 00:14:32 | Clock: 21:44:32) [Clutch] 1v3 Sheriff clutch on A site
[00:42:25 - 00:42:45] (Elapsed: 00:42:45 | Clock: 22:12:45) [Funny] Teammate team-flashed everyone
[01:15:30 - 01:15:50] (Elapsed: 01:15:50 | Clock: 22:45:50) [Clip] Insane operator collateral shot
```

---

## 🛠️ Customization & Tips

- **Change Lookback Window**: In `Tools -> Scripts -> stream_marker.lua`, you can change the lookback duration to 30s, 45s, or 60s.
- **Recording Without Streaming**: If you use OBS for local recording instead of streaming, the plugin automatically detects when recording starts and tracks elapsed recording time instead.
- **Offline Testing**: You can test the hotkey and dock even while offline; markers will simply track elapsed session time.
