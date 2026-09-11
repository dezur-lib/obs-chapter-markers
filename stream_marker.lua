-- ============================================================================
-- OBS Stream Highlight Marker - Lua Script
-- ============================================================================
-- Description:
--   Lightweight stream marker utility for OBS Studio.
--   Allows setting a global shortcut to mark clippable moments during a stream
--   with ZERO GPU/RAM overhead (no replay buffer or video encoding needed).
--   Saves markers to JSON (for OBS Browser Dock) and formatted TXT files.
-- ============================================================================

local obs = obslua

-- Configuration State
local config = {
    output_dir = "",
    stream_title = "My Stream",
    auto_detect_title = true,
    lookback_seconds = 20,
    auto_save_txt = true
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

-- ----------------------------------------------------------------------------
-- Auto-Detect Stream Title (YouTube Broadcast / Twitch Stream Info)
-- ----------------------------------------------------------------------------

local function detect_active_stream_title()
    local profile = obs.obs_frontend_get_current_profile()
    if not profile or profile == "" then
        return nil
    end

    local candidates = {}
    local appdata = os.getenv("APPDATA")
    if appdata then
        table.insert(candidates, appdata .. "\\obs-studio\\basic\\profiles\\" .. profile .. "\\basic.ini")
        table.insert(candidates, appdata .. "/obs-studio/basic/profiles/" .. profile .. "/basic.ini")
    end
    table.insert(candidates, "C:\\obs-studio\\config\\obs-studio\\basic\\profiles\\" .. profile .. "\\basic.ini")
    table.insert(candidates, "C:/obs-studio/config/obs-studio/basic/profiles/" .. profile .. "/basic.ini")

    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            local current_section = ""
            local yt_title = nil
            local twitch_title = nil
            local generic_title = nil

            for line in f:lines() do
                local sec = line:match("^%[([^%]]+)%]")
                if sec then
                    current_section = sec:lower()
                else
                    local key, val = line:match("^([^=]+)=(.*)$")
                    if key and val then
                        local k = key:lower():gsub("%s+", "")
                        local v = val:gsub("^%s+", ""):gsub("%s+$", "")
                        if k == "title" and v ~= "" then
                            if current_section:find("youtube") then
                                yt_title = v
                            elseif current_section:find("twitch") then
                                twitch_title = v
                            else
                                generic_title = v
                            end
                        end
                    end
                end
            end
            f:close()

            local detected = yt_title or twitch_title or generic_title
            if detected and detected ~= "" then
                return detected
            end
        end
    end

    -- Fallback: Check streaming service settings
    local service = obs.obs_frontend_get_streaming_service()
    if service then
        local s_settings = obs.obs_service_get_settings(service)
        if s_settings then
            local t = obs.obs_data_get_string(s_settings, "stream_title")
            if not t or t == "" then t = obs.obs_data_get_string(s_settings, "title") end
            if not t or t == "" then t = obs.obs_data_get_string(s_settings, "broadcast_title") end
            obs.obs_data_release(s_settings)
            if t and t ~= "" then return t end
        end
    end

    return nil
end

local function periodic_title_check()
    if config.auto_detect_title then
        local auto = detect_active_stream_title()
        if auto and auto ~= "" and auto ~= config.stream_title then
            config.stream_title = auto
            obs.blog(obs.LOG_INFO, "[StreamMarker] Broadcast title changed to: " .. auto)
            write_live_json()
        end
    end
end

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
    table.insert(parts, '  "lookback_seconds": ' .. config.lookback_seconds .. ',\n')
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

local function write_live_json()
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

local function get_session_txt_filepath()
    local dir = get_target_output_dir()
    local date_str = os.date("%Y-%m-%d")
    local title_slug = sanitize_filename(config.stream_title)
    return string.format("%s%s_%s_markers.txt", dir, title_slug, date_str)
end

local function append_marker_to_txt(marker)
    if not config.auto_save_txt then return end
    local filepath = get_session_txt_filepath()
    local exists = io.open(filepath, "r")
    local is_new = (exists == nil)
    if exists then exists:close() end

    local file = io.open(filepath, "a+")
    if file then
        if is_new then
            file:write("================================================================\n")
            file:write("STREAM HIGHLIGHT MARKERS: " .. config.stream_title .. "\n")
            file:write("Date: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
            file:write("Format: [Clip Range] (Elapsed) - Tag: Note\n")
            file:write("================================================================\n\n")
        end

        local line = string.format(
            "[%s - %s] (Elapsed: %s | Clock: %s) [%s] %s\n",
            marker.start_time,
            marker.timestamp,
            marker.timestamp,
            marker.clock_time,
            marker.tag or "Clip",
            (marker.note and marker.note ~= "") and marker.note or "Highlight moment"
        )
        file:write(line)
        file:close()
    else
        obs.blog(obs.LOG_WARNING, "[StreamMarker] Unable to open TXT for append: " .. filepath)
    end
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

local function add_marker(tag, note, force_allow)
    -- Do not mark if user is neither streaming nor recording
    if not force_allow and not is_session_active() then
        obs.blog(obs.LOG_INFO, "[StreamMarker] Marker ignored: Not streaming or recording.")
        return
    end

    -- Check if broadcast title updated (e.g. selected existing broadcast)
    if config.auto_detect_title and session.streaming then
        local auto = detect_active_stream_title()
        if auto and auto ~= "" and auto ~= config.stream_title then
            config.stream_title = auto
            obs.blog(obs.LOG_INFO, "[StreamMarker] Active broadcast title refreshed: " .. auto)
        end
    end

    local elapsed = get_active_elapsed_seconds()
    local clip_start_sec = math.max(0, elapsed - config.lookback_seconds)
    local clock_time_str = os.date("%H:%M:%S")

    local marker = {
        id = #session.markers + 1,
        timestamp = get_timestamp_string(elapsed),
        start_time = get_timestamp_string(clip_start_sec),
        elapsed_seconds = elapsed,
        clock_time = clock_time_str,
        tag = tag or "Clip",
        note = note or ""
    }

    table.insert(session.markers, marker)
    obs.blog(obs.LOG_INFO, string.format("[StreamMarker] Marked #%d at %s (Lookback: %s)", marker.id, marker.timestamp, marker.start_time))

    -- Save state
    write_live_json()
    append_marker_to_txt(marker)
end

-- ----------------------------------------------------------------------------
-- Hotkey Handler
-- ----------------------------------------------------------------------------

local last_hotkey_epoch = 0

local function on_marker_hotkey(pressed)
    if not pressed then return end
    -- Only trigger hotkey if user is actively streaming or recording
    if not is_session_active() then
        return
    end

    local now = get_current_epoch()
    -- 2-second cooldown to prevent duplicate triggers
    if (now - last_hotkey_epoch) < 2 then
        return
    end
    last_hotkey_epoch = now
    add_marker("Clip", "")
end

-- ----------------------------------------------------------------------------
-- OBS Frontend Event Callback (Stream Start / Stop / Record)
-- ----------------------------------------------------------------------------

local function on_frontend_event(event)
    local now = get_current_epoch()

    if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then
        session.streaming = true
        session.stream_start_time = now
        session.session_id = os.date("%Y%m%d_%H%M%S")

        if config.auto_detect_title then
            local auto = detect_active_stream_title()
            if auto and auto ~= "" then
                config.stream_title = auto
                obs.blog(obs.LOG_INFO, "[StreamMarker] Auto-detected stream title: " .. auto)
            end
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
            session.session_id = os.date("%Y%m%d_%H%M%S")
            if config.auto_detect_title then
                local auto = detect_active_stream_title()
                if auto and auto ~= "" then
                    config.stream_title = auto
                    obs.blog(obs.LOG_INFO, "[StreamMarker] Auto-detected stream title: " .. auto)
                end
            end
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
  <li>Press the shortcut during gameplay/livestream to mark clippable moments.</li>
  <li>Auto-detects stream title from OBS YouTube/Twitch broadcast info.</li>
  <li>Auto-calculates elapsed stream time and lookback duration (pre-roll).</li>
  <li>Displays markers dynamically in the <b>OBS Browser Dock</b>.</li>
  <li>Automatically exports to <code>.txt</code> with stream title.</li>
</ul>
<p><i>Set your shortcut key in: <b>Settings &rarr; Hotkeys &rarr; Stream Marker: Mark Clip Point</b></i></p>
]]
end

function script_properties()
    local props = obs.obs_properties_create()

    obs.obs_properties_add_bool(props, "auto_detect_title", "Auto-detect Stream Title (YouTube/Twitch)")
    obs.obs_properties_add_text(props, "stream_title", "Manual Stream Title / Game", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int(props, "lookback_seconds", "Lookback Pre-Roll (Seconds)", 5, 120, 5)
    obs.obs_properties_add_path(props, "output_dir", "Output Folder (Save markers to)", obs.OBS_PATH_DIRECTORY, "", nil)
    obs.obs_properties_add_bool(props, "auto_save_txt", "Auto-append to TXT on marker")

    local btn_mark = obs.obs_properties_add_button(props, "btn_test_mark", "Trigger Test Marker Now", function()
        add_marker("Test", "Manual test marker from script properties")
        return true
    end)

    local btn_clear = obs.obs_properties_add_button(props, "btn_clear_session", "Clear Current Session Markers", function()
        session.markers = {}
        write_live_json()
        obs.blog(obs.LOG_INFO, "[StreamMarker] Session markers cleared.")
        return true
    end)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_bool(settings, "auto_detect_title", true)
    obs.obs_data_set_default_string(settings, "stream_title", "My Stream Session")
    obs.obs_data_set_default_int(settings, "lookback_seconds", 20)
    obs.obs_data_set_default_string(settings, "output_dir", get_script_dir())
    obs.obs_data_set_default_bool(settings, "auto_save_txt", true)
end

function script_update(settings)
    config.auto_detect_title = obs.obs_data_get_bool(settings, "auto_detect_title")
    config.stream_title = obs.obs_data_get_string(settings, "stream_title")
    config.lookback_seconds = obs.obs_data_get_int(settings, "lookback_seconds")
    config.output_dir = obs.obs_data_get_string(settings, "output_dir")
    config.auto_save_txt = obs.obs_data_get_bool(settings, "auto_save_txt")

    if config.auto_detect_title then
        local auto = detect_active_stream_title()
        if auto and auto ~= "" then
            config.stream_title = auto
        end
    end

    -- Ensure trailing slash
    if config.output_dir ~= "" and not config.output_dir:match("[/\\]$") then
        config.output_dir = config.output_dir .. "/"
    end

    write_live_json()
end

function script_load(settings)
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

    -- Auto-detect title on load
    if config.auto_detect_title then
        local auto = detect_active_stream_title()
        if auto and auto ~= "" then
            config.stream_title = auto
            obs.blog(obs.LOG_INFO, "[StreamMarker] Initialized with auto-detected title: " .. auto)
        end
    end

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

    -- Start periodic background check for broadcast title changes (every 2 seconds)
    obs.timer_add(periodic_title_check, 2000)

    obs.blog(obs.LOG_INFO, "[StreamMarker] Stream Marker Plugin loaded successfully.")
end

function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
    obs.obs_data_set_array(settings, "stream_marker_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

function script_unload()
    obs.timer_remove(periodic_title_check)
    obs.obs_frontend_remove_event_callback(on_frontend_event)
    obs.blog(obs.LOG_INFO, "[StreamMarker] Unloaded.")
end
