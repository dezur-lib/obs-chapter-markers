local obs = obslua

-- Configuration State
local config = {
    output_dir = "",
    stream_title = "My Stream",
    auto_save_txt = true,
    boss_name = ""
}

-- Session State
local session = {
    streaming = false,
    recording = false,
    stream_start_time = 0,
    recording_start_time = 0,
    session_id = "",
    markers = {}
}

local hotkey_id = obs.OBS_INVALID_HOTKEY_ID

-- Number of chapter presses so far for the current boss.
-- Odd presses are Pulls, even presses are Wipes: Pull 1, Wipe 1, Pull 2, Wipe 2...
local chapter_counter = 0

-- Boss name currently appended to chapter names (set with the Apply Boss Name button)
local active_boss = ""

-- Forward declaration (defined in the File I/O section below)
local write_live_json

-- ----------------------------------------------------------------------------
-- Utility Functions
-- ----------------------------------------------------------------------------

local function get_timestamp_string(total_seconds)
    if total_seconds < 0 then total_seconds = 0 end
    local hours = math.floor(total_seconds / 3600)
    local mins = math.floor((total_seconds % 3600) / 60)
    local secs = math.floor(total_seconds % 60)
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

local function get_current_epoch()
    return os.time()
end

local function clean_text(s)
    s = s or ""
    s = s:gsub("[\r\n]+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function sanitize_filename(name)
    if not name or name == "" then return "Stream" end
    -- replace invalid filename chars
    local clean = name:gsub('[\\/:*?"<>|]', "_")
    clean = clean:gsub("%s+", "_")
    return clean:sub(1, 50)
end

local function get_script_dir()
    return script_path():match("(.*[/\\])") or ""
end

local function get_target_output_dir()
    if config.output_dir and config.output_dir ~= "" then
        return config.output_dir
    end
    -- Fallback to script directory
    return get_script_dir()
end

-- ----------------------------------------------------------------------------
-- JSON Serializer (Pure Lua, zero dependencies)
-- ----------------------------------------------------------------------------
local function escape_json_str(str)
    if not str then return '""' end
    str = str:gsub('\\', '\\\\')
    str = str:gsub('"', '\\"')
    str = str:gsub('\n', '\\n')
    str = str:gsub('\r', '\\r')
    str = str:gsub('\t', '\\t')
    return '"' .. str .. '"'
end

local function serialize_markers_json()
    local parts = {}
    table.insert(parts, '{\n')
    table.insert(parts, '  "stream_title": ' .. escape_json_str(config.stream_title) .. ',\n')
    table.insert(parts, '  "session_id": ' .. escape_json_str(session.session_id) .. ',\n')
    table.insert(parts, '  "is_streaming": ' .. (session.streaming and "true" or "false") .. ',\n')
    table.insert(parts, '  "is_recording": ' .. (session.recording and "true" or "false") .. ',\n')
    table.insert(parts, '  "stream_start_time": ' .. session.stream_start_time .. ',\n')
    table.insert(parts, '  "markers": [\n')

    for i, m in ipairs(session.markers) do
        local comma = (i < #session.markers) and ',' or ''
        local m_json = string.format(
            '    {\n      "id": %d,\n      "timestamp": "%s",\n      "start_time": "%s",\n      "elapsed_seconds": %d,\n      "clock_time": "%s",\n      "tag": %s,\n      "note": %s\n    }%s\n',
            m.id,
            m.timestamp,
            m.start_time,
            m.elapsed_seconds,
            m.clock_time,
            escape_json_str(m.tag or "Clip"),
            escape_json_str(m.note or ""),
            comma
        )
        table.insert(parts, m_json)
    end

    table.insert(parts, '  ]\n}\n')
    return table.concat(parts)
end

-- ----------------------------------------------------------------------------
-- File I/O
-- ----------------------------------------------------------------------------

function write_live_json()
    local dir = get_target_output_dir()
    local json_str = serialize_markers_json()

    -- 1. Write markers_live.json
    local filepath = dir .. "markers_live.json"
    local file = io.open(filepath, "w+")
    if file then
        file:write(json_str)
        file:close()
    else
        obs.blog(obs.LOG_WARNING, "[StreamMarker] Unable to open for writing: " .. filepath)
    end

    -- 2. Write dock/markers_data.js to enable seamless browser dock integration without CORS issues
    local script_dir = get_script_dir()
    local dock_filepath = script_dir .. "dock/markers_data.js"
    local dock_file = io.open(dock_filepath, "w+")
    if dock_file then
        local js_wrapper = "window.__OBS_MARKERS_DATA__ = " .. json_str .. ";\n" ..
                           "if (typeof window.onObsMarkersUpdate === 'function') { window.onObsMarkersUpdate(window.__OBS_MARKERS_DATA__); }\n"
        dock_file:write(js_wrapper)
        dock_file:close()
    else
        -- Fallback if dock directory is relative to output dir
        local fallback_path = dir .. "dock/markers_data.js"
        local fb_file = io.open(fallback_path, "w+")
        if fb_file then
            local js_wrapper = "window.__OBS_MARKERS_DATA__ = " .. json_str .. ";\n" ..
                               "if (typeof window.onObsMarkersUpdate === 'function') { window.onObsMarkersUpdate(window.__OBS_MARKERS_DATA__); }\n"
            fb_file:write(js_wrapper)
            fb_file:close()
        end
    end
end

-- Each session gets its own file: Title_YYYYMMDD_HHMMSS_markers.txt
local function get_session_txt_filepath()
    local dir = get_target_output_dir()
    local title_slug = sanitize_filename(config.stream_title)
    return string.format("%s%s_%s_markers.txt", dir, title_slug, session.session_id)
end

-- Appends a marker to the session .txt. Returns the file path if written, nil otherwise.
local function append_marker_to_txt(marker)
    if not config.auto_save_txt then return nil end
    local filepath = get_session_txt_filepath()
    local exists = io.open(filepath, "r")
    local is_new = (exists == nil)
    if exists then exists:close() end

    local file = io.open(filepath, "a+")
    if file then
        -- Every new file starts with the required zero-point chapter
        if is_new then
            file:write("0:00:00 - VOD Start\n")
        end

        -- Strip zero-padding from the hour only: 00:02:12 -> 0:02:12
        local chapter_time = (marker.timestamp:gsub("^0(%d):", "%1:"))
        local chapter_text = (marker.note and marker.note ~= "") and marker.note or "Chapter"
        file:write(chapter_time .. " - " .. chapter_text .. "\n")
        file:close()
        return filepath
    else
        obs.blog(obs.LOG_WARNING, "[StreamMarker] Unable to open TXT for append: " .. filepath)
        return nil
    end
end

-- Deletes the last line of a text file. Returns true on success.
local function remove_last_txt_line(filepath)
    local f = io.open(filepath, "r")
    if not f then return false end
    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()

    if #lines == 0 then return false end
    table.remove(lines)

    local out = io.open(filepath, "w+")
    if not out then return false end
    for _, l in ipairs(lines) do
        out:write(l .. "\n")
    end
    out:close()
    return true
end

-- ----------------------------------------------------------------------------
-- Marker Generation Logic
-- ----------------------------------------------------------------------------

local function get_active_elapsed_seconds()
    local now = get_current_epoch()
    if session.streaming and session.stream_start_time > 0 then
        return now - session.stream_start_time
    elseif session.recording and session.recording_start_time > 0 then
        return now - session.recording_start_time
    else
        -- When neither streaming nor recording is active, track relative to script start
        return 0
    end
end

local function is_session_active()
    return obs.obs_frontend_streaming_active() or obs.obs_frontend_recording_active() or session.streaming or session.recording
end

-- Starts a fresh session: empties the marker list, restarts Pull/Wipe numbering,
-- and creates a new session ID (which means a new .txt file on the next marker).
-- Elapsed time is NOT reset, so timestamps stay in sync with the actual VOD.
local function reset_session()
    session.markers = {}
    chapter_counter = 0
    session.session_id = os.date("%Y%m%d_%H%M%S")
end

-- Creates a marker at the current moment and writes it immediately.
-- Returns true if the marker was written, false if it was ignored.
local function add_marker(tag, note, force_allow)
    -- Do not mark if user is neither streaming nor recording
    if not force_allow and not is_session_active() then
        print("[StreamMarker] Marker ignored: not streaming or recording.")
        return false
    end

    local elapsed = get_active_elapsed_seconds()
    local timestamp_str = get_timestamp_string(elapsed)
    local clock_time_str = os.date("%H:%M:%S")

    local marker = {
        id = #session.markers + 1,
        timestamp = timestamp_str,
        start_time = timestamp_str,
        elapsed_seconds = elapsed,
        clock_time = clock_time_str,
        tag = tag or "Clip",
        note = note or "",
        txt_path = nil
    }

    table.insert(session.markers, marker)
    print(string.format("[StreamMarker] Saved #%d at %s: %s", marker.id, marker.timestamp, marker.note))

    write_live_json()
    -- Remember which file the line went to so Undo can remove it
    marker.txt_path = append_marker_to_txt(marker)
    return true
end

-- Shared by the hotkey and the Save Chapter button.
-- Press 1 = Pull 1, press 2 = Wipe 1, press 3 = Pull 2, press 4 = Wipe 2, ...
-- If a boss name is applied, it is appended: "Pull 1 - Boss Name"
local function mark_chapter()
    local press_number = chapter_counter + 1
    local attempt = math.ceil(press_number / 2)
    local label = (press_number % 2 == 1) and "Pull" or "Wipe"
    local name = label .. " " .. attempt
    if active_boss ~= "" then
        name = name .. " - " .. active_boss
    end

    -- Only advance the counter if the marker was actually written
    if add_marker(label, name) then
        chapter_counter = press_number
    end
end

-- Removes the most recent marker from the session, the JSON/dock data, and the .txt.
local function undo_last_marker()
    local m = table.remove(session.markers)
    if not m then
        print("[StreamMarker] Nothing to undo.")
        return false
    end

    if m.txt_path then
        remove_last_txt_line(m.txt_path)
    end

    chapter_counter = math.max(0, chapter_counter - 1)
    write_live_json()
    print(string.format("[StreamMarker] Undid #%d (%s).", m.id, m.note))
    return true
end

-- ----------------------------------------------------------------------------
-- Hotkey Handler
-- ----------------------------------------------------------------------------

local last_hotkey_epoch = 0

local function on_marker_hotkey(pressed)
    if not pressed then return end
    -- Only trigger hotkey if user is actively streaming or recording
    if not is_session_active() then
        print("[StreamMarker] Hotkey ignored: not streaming or recording.")
        return
    end

    local now = get_current_epoch()
    -- 2-second cooldown to prevent duplicate triggers
    if (now - last_hotkey_epoch) < 2 then
        return
    end
    last_hotkey_epoch = now
    mark_chapter()
end

-- ----------------------------------------------------------------------------
-- OBS Frontend Event Callback (Stream Start / Stop / Record)
-- ----------------------------------------------------------------------------

local function on_frontend_event(event)
    local now = get_current_epoch()

    if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then
        session.streaming = true
        session.stream_start_time = now
        -- New stream: start a fresh session (unless a recording is already running)
        if not session.recording then
            reset_session()
        end

        obs.blog(obs.LOG_INFO, "[StreamMarker] Stream started. Session: " .. session.session_id)
        write_live_json()

    elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then
        session.streaming = false
        obs.blog(obs.LOG_INFO, "[StreamMarker] Stream stopped.")
        write_live_json()

    elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
        session.recording = true
        session.recording_start_time = now
        if not session.streaming then
            reset_session()
        end
        obs.blog(obs.LOG_INFO, "[StreamMarker] Recording started.")
        write_live_json()

    elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
        session.recording = false
        obs.blog(obs.LOG_INFO, "[StreamMarker] Recording stopped.")
        write_live_json()
    end
end

-- ----------------------------------------------------------------------------
-- Script Properties & Lifecycle Hooks
-- ----------------------------------------------------------------------------

function script_description()
    return [[
<h2>Stream Highlight Marker</h2>
<p>Lightweight marker tool with <b>zero GPU/RAM overhead</b>.</p>
<ul>
  <li>Press the shortcut (or click <b>Save Chapter</b>) to write a chapter timestamp to the .txt.</li>
  <li>Every new .txt starts with <b>0:00:00 - VOD Start</b>.</li>
  <li>Presses alternate automatically: <b>Pull 1, Wipe 1, Pull 2, Wipe 2...</b></li>
  <li>Type a <b>Boss name</b> and click <b>Apply Boss Name</b> to append it to every chapter that follows. Applying a boss name also <b>resets the count to Pull 1</b>.</li>
  <li><b>Undo Last Marker</b> removes the most recent chapter.</li>
  <li><b>Clear Current Session Markers</b> starts a brand new session and a new .txt file.</li>
  <li>Displays markers dynamically in the <b>OBS Browser Dock</b>.</li>
</ul>
<p><i>Set your shortcut key in: <b>Settings &rarr; Hotkeys &rarr; Stream Marker: Mark Clip Point</b></i></p>
]]
end

function script_properties()
    local props = obs.obs_properties_create()

    obs.obs_properties_add_text(props, "stream_title", "Stream Title (used in file name)", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_path(props, "output_dir", "Output Folder (Save markers to)", obs.OBS_PATH_DIRECTORY, "", nil)
    obs.obs_properties_add_bool(props, "auto_save_txt", "Auto-append to TXT on marker")

    obs.obs_properties_add_text(props, "boss_name", "Boss name", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(props, "btn_apply_boss", "Apply Boss Name", function()
        active_boss = clean_text(config.boss_name)
        -- New boss: restart Pull/Wipe numbering so the next press is Pull 1
        chapter_counter = 0
        if active_boss == "" then
            print("[StreamMarker] Boss name cleared. Pull/Wipe numbering reset.")
        else
            print("[StreamMarker] Boss name applied: " .. active_boss .. ". Pull/Wipe numbering reset.")
        end
        return true
    end)

    obs.obs_properties_add_button(props, "btn_save_chapter", "Save Chapter", function()
        mark_chapter()
        return true
    end)

    obs.obs_properties_add_button(props, "btn_undo_marker", "Undo Last Marker", function()
        undo_last_marker()
        return true
    end)

    obs.obs_properties_add_button(props, "btn_clear_session", "Clear Current Session Markers", function()
        reset_session()
        write_live_json()
        print("[StreamMarker] New session started: " .. session.session_id .. ". Markers cleared, Pull/Wipe numbering reset, new .txt will be created on the next marker.")
        return true
    end)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "stream_title", "My Stream Session")
    obs.obs_data_set_default_string(settings, "output_dir", get_script_dir())
    obs.obs_data_set_default_bool(settings, "auto_save_txt", true)
    obs.obs_data_set_default_string(settings, "boss_name", "")
end

function script_update(settings)
    config.stream_title = obs.obs_data_get_string(settings, "stream_title")
    config.output_dir = obs.obs_data_get_string(settings, "output_dir")
    config.auto_save_txt = obs.obs_data_get_bool(settings, "auto_save_txt")
    config.boss_name = obs.obs_data_get_string(settings, "boss_name")

    -- Ensure trailing slash
    if config.output_dir ~= "" and not config.output_dir:match("[/\\]$") then
        config.output_dir = config.output_dir .. "/"
    end

    write_live_json()
end

function script_load(settings)
    -- Keep the previously applied boss name if the script is reloaded
    active_boss = clean_text(obs.obs_data_get_string(settings, "boss_name"))

    -- Register global hotkey in OBS
    hotkey_id = obs.obs_hotkey_register_frontend(
        "stream_marker_trigger",
        "Stream Marker: Mark Clip Point",
        on_marker_hotkey
    )
    local hotkey_save_array = obs.obs_data_get_array(settings, "stream_marker_hotkey")
    obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    -- Register OBS stream/record state change events
    obs.obs_frontend_add_event_callback(on_frontend_event)

    -- Check if currently streaming or recording on script load
    if obs.obs_frontend_streaming_active() then
        session.streaming = true
        session.stream_start_time = get_current_epoch()
    end
    if obs.obs_frontend_recording_active() then
        session.recording = true
        session.recording_start_time = get_current_epoch()
    end

    session.session_id = os.date("%Y%m%d_%H%M%S")
    write_live_json()

    obs.blog(obs.LOG_INFO, "[StreamMarker] Stream Marker Plugin loaded successfully.")
end

function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
    obs.obs_data_set_array(settings, "stream_marker_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

function script_unload()
    obs.obs_frontend_remove_event_callback(on_frontend_event)
    obs.blog(obs.LOG_INFO, "[StreamMarker] Unloaded.")
end