# 🎬 OBS Stream Highlight Marker

A modified version of @Aischii's lightweight, **zero-GPU / zero-RAM overhead** stream marker plugin for **OBS Studio**. 

Instead of running a heavy background replay buffer (like Medal or Shadowplay), this script timestamps boss pulls and wipes whenever you hit a hotkey while gaming. It syncs with your stream elapsed time, and exports formatted, YouTube-ready timestamps for you.

---

## ⚡ Highlights

- **0% Extra GPU / RAM**: No replay buffer, no frame caching, no encoder lag.
- **Global In-Game Hotkey**: Works seamlessly while playing full-screen exclusive games.
- **Active Guard**: Prevents accidental hotkey triggers when you're not live or recording.

---

## 🚀 Quick Setup (3 Steps)

### 1. Add Script
In OBS &rarr; **Tools** &rarr; **Scripts** &rarr; click **`+`** &rarr; select `stream_markers_v3.lua`.

### 2. Set Shortcut Key
In OBS &rarr; **Settings** &rarr; **Hotkeys** &rarr; search `Stream Marker: Mark Clip Point` &rarr; bind your key (e.g. `F8`).

### 3. Configure Boss Names & Output Folder
In OBS &rarr; **Tools** &rarr; **Scripts** &rarr; select `stream_markers_v3.lua` &rarr; click 'Browse' &rarr; select a folder location to output the .txt file &rarr; input a boss name and click 'Apply Boss Name'

---

## 🎮 How It Works

```text
[Gaming Live] ──(Press Hotkey)──> [OBS Captures Timestamp] ──> [Chapters are automatically recorded and saved to .TXT]
```

1. Start streaming or recording in OBS.
2. Whenever a pull or wipe occurs, hit your shortcut key (e.g. `F8`).
3. The tool will mark a Pull on first press and a Wipe on second press using your configured boss name.
4. Your timestamps are automatically saved to .TXT as you go.

---

## ⚙️ Configuration

In **Tools &rarr; Scripts &rarr; stream_marker.lua**:
- **Stream Title**: Used for naming the .TXT file.
- **Boss Name**: The name of the boss you're currently fighting/progressing.
- **Output Folder**: Destination folder for saved `.txt` marker logs.

---

## 📜 License

MIT License © [Aischii](https://github.com/Aischii)
