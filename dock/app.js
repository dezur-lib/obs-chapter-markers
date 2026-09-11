// ============================================================================
// OBS Stream Marker - Browser Dock Logic
// ============================================================================

(function () {
  // Application State
  const state = {
    streamTitle: 'My Livestream',
    sessionId: '',
    isStreaming: false,
    isRecording: false,
    streamStartTime: 0,
    lookbackSeconds: 20,
    activeTag: 'Clip',
    markers: [],
    soundEnabled: true
  };

  // Persistent tracking of deleted markers so they never reappear
  const STORAGE_KEY_DELETED = 'obs_marker_deleted_ids';
  let deletedMarkerIds = new Set();
  try {
    const saved = localStorage.getItem(STORAGE_KEY_DELETED);
    if (saved) {
      deletedMarkerIds = new Set(JSON.parse(saved));
    }
  } catch (_) {}

  function persistDeletedIds() {
    try {
      localStorage.setItem(STORAGE_KEY_DELETED, JSON.stringify([...deletedMarkerIds]));
    } catch (_) {}
  }

  // Audio Context (Synthesized chime via Web Audio API)
  let audioCtx = null;

  function initAudio() {
    if (!audioCtx) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (AudioContextClass) {
        audioCtx = new AudioContextClass();
      }
    }
  }

  function playChime() {
    if (!state.soundEnabled) return;
    try {
      initAudio();
      if (!audioCtx) return;
      if (audioCtx.state === 'suspended') {
        audioCtx.resume();
      }

      const now = audioCtx.currentTime;

      // First note (D5 - 587.33Hz)
      const osc1 = audioCtx.createOscillator();
      const gain1 = audioCtx.createGain();
      osc1.type = 'sine';
      osc1.frequency.setValueAtTime(587.33, now);
      gain1.gain.setValueAtTime(0.12, now);
      gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.25);
      osc1.connect(gain1);
      gain1.connect(audioCtx.destination);
      osc1.start(now);
      osc1.stop(now + 0.25);

      // Second note (A5 - 880Hz)
      const osc2 = audioCtx.createOscillator();
      const gain2 = audioCtx.createGain();
      osc2.type = 'sine';
      osc2.frequency.setValueAtTime(880.0, now + 0.08);
      gain2.gain.setValueAtTime(0.12, now + 0.08);
      gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.45);
      osc2.connect(gain2);
      gain2.connect(audioCtx.destination);
      osc2.start(now + 0.08);
      osc2.stop(now + 0.45);
    } catch (e) {
      console.warn('Audio chime failed:', e);
    }
  }

  // DOM Elements
  const elStreamTitle = document.getElementById('stream-title-input');
  const elStatusDot = document.getElementById('status-dot');
  const elStatusText = document.getElementById('status-text');
  const elLiveTimer = document.getElementById('live-timer');
  const elLookbackVal = document.getElementById('lookback-val');
  const elBtnQuickMark = document.getElementById('btn-quick-mark');
  const elBtnSound = document.getElementById('btn-sound-toggle');
  const elSoundIconOn = document.getElementById('sound-icon-on');
  const elSoundIconOff = document.getElementById('sound-icon-off');
  const elTagPresets = document.getElementById('tag-presets');
  const elMarkersList = document.getElementById('markers-list');
  const elMarkerCount = document.getElementById('marker-count');
  const elBtnClearAll = document.getElementById('btn-clear-all');
  const elBtnExportTxt = document.getElementById('btn-export-txt');
  const elBtnCopy = document.getElementById('btn-copy-clipboard');
  const elBtnExportMore = document.getElementById('btn-export-more');
  const elExportDropdown = document.getElementById('export-dropdown');
  const elToast = document.getElementById('toast-notify');

  // Format seconds to HH:MM:SS
  function formatTime(totalSeconds) {
    if (isNaN(totalSeconds) || totalSeconds < 0) totalSeconds = 0;
    const h = Math.floor(totalSeconds / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    const s = Math.floor(totalSeconds % 60);
    return [h, m, s].map((v) => String(v).padStart(2, '0')).join(':');
  }

  function showToast(msg) {
    elToast.textContent = msg;
    elToast.classList.remove('hidden');
    setTimeout(() => {
      elToast.classList.add('hidden');
    }, 2200);
  }

  // Get current active elapsed time
  function getCurrentElapsedSeconds() {
    if (state.isStreaming && state.streamStartTime > 0) {
      return Math.max(0, Math.floor(Date.now() / 1000 - state.streamStartTime));
    }
    return 0;
  }

  // Live timer interval (every 1 sec)
  setInterval(() => {
    if (state.isStreaming || state.isRecording) {
      const elapsed = getCurrentElapsedSeconds();
      elLiveTimer.textContent = formatTime(elapsed);
    } else {
      elLiveTimer.textContent = '00:00:00';
    }
  }, 1000);

  // Render Marker Cards
  function renderMarkers() {
    elMarkerCount.textContent = state.markers.length;

    if (state.markers.length === 0) {
      elMarkersList.innerHTML = `
        <div id="empty-state" class="empty-state">
          <div class="empty-icon">📍</div>
          <p class="empty-title">No Markers Yet</p>
          <p class="empty-sub">Press your <b>OBS Hotkey</b> while streaming or gaming to mark clip points automatically.</p>
        </div>
      `;
      return;
    }

    // Render in reverse chronological order (newest on top)
    let html = '';
    const reversed = [...state.markers].reverse();

    reversed.forEach((m) => {
      html += `
        <div class="marker-card" data-id="${m.id}">
          <div class="marker-header">
            <div class="marker-times">
              <span class="marker-timestamp">${m.timestamp}</span>
              <span class="marker-range">(${m.start_time} - ${m.timestamp})</span>
            </div>
            <span class="marker-tag-badge">${escapeHtml(m.tag || 'Clip')}</span>
          </div>
          <input type="text" class="marker-note-input" placeholder="Add note (e.g. 1v4 clutch, hilarious bug)..." value="${escapeHtml(m.note || '')}" data-id="${m.id}">
          <div class="marker-footer">
            <span>Clock: ${m.clock_time || '--:--:--'}</span>
            <button class="btn-card-del" data-id="${m.id}" title="Remove marker">✕</button>
          </div>
        </div>
      `;
    });

    elMarkersList.innerHTML = html;
  }

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  // Add marker manually from dock UI
  function addManualMarker() {
    if (!state.isStreaming && !state.isRecording) {
      showToast('⚠️ Start streaming or recording first!');
      return;
    }

    const elapsed = getCurrentElapsedSeconds();
    const clipStartSec = Math.max(0, elapsed - state.lookbackSeconds);
    const date = new Date();
    const clockStr = [date.getHours(), date.getMinutes(), date.getSeconds()]
      .map((v) => String(v).padStart(2, '0'))
      .join(':');

    const newMarker = {
      id: Date.now(),
      timestamp: formatTime(elapsed),
      start_time: formatTime(clipStartSec),
      elapsed_seconds: elapsed,
      clock_time: clockStr,
      tag: state.activeTag,
      note: ''
    };

    state.markers.push(newMarker);
    renderMarkers();
    playChime();
    showToast(`Marked #${state.markers.length} at ${newMarker.timestamp}`);
  }

  // Update UI and state with received OBS data
  function updateWithData(data) {
    if (!data) return;

    if (data.stream_title && data.stream_title !== state.streamTitle && document.activeElement !== elStreamTitle) {
      state.streamTitle = data.stream_title;
      elStreamTitle.value = data.stream_title;
    }

    if (data.lookback_seconds) {
      state.lookbackSeconds = data.lookback_seconds;
      elLookbackVal.textContent = `${data.lookback_seconds}s`;
    }

    const streaming = !!data.is_streaming;
    if (streaming !== state.isStreaming) {
      state.isStreaming = streaming;
      elStatusDot.className = `status-dot ${streaming ? 'live' : 'offline'}`;
      elStatusText.textContent = streaming ? 'LIVE' : 'OFFLINE';
    }

    if (data.stream_start_time) {
      state.streamStartTime = data.stream_start_time;
    }

    if (data.session_id && data.session_id !== state.sessionId) {
      state.sessionId = data.session_id;
      // New stream session: clear deleted IDs
      deletedMarkerIds.clear();
      persistDeletedIds();
    }

    if (Array.isArray(data.markers)) {
      // Filter out any markers that the user explicitly deleted
      const validMarkers = data.markers.filter((m) => !deletedMarkerIds.has(m.id));

      // Check if the marker set actually changed (different count or different IDs)
      const countChanged = state.markers.length !== validMarkers.length;
      const idsChanged = validMarkers.some((m, idx) => !state.markers[idx] || state.markers[idx].id !== m.id);

      if (countChanged || idsChanged) {
        // Detect if a brand-new marker was added
        const existingIds = new Set(state.markers.map((m) => m.id));
        const hasNewIncoming = validMarkers.some((m) => !existingIds.has(m.id));

        if (hasNewIncoming && state.markers.length > 0) {
          playChime();
          showToast(`New Hotkey Marker Added!`);
        }

        // Preserve any user-typed notes in existing cards
        const noteMap = new Map(state.markers.map((m) => [m.id, m.note]));
        state.markers = validMarkers.map((m) => ({
          ...m,
          note: noteMap.has(m.id) ? noteMap.get(m.id) : (m.note || '')
        }));

        // Re-render only when markers actually changed
        renderMarkers();
      }
    }
  }

  // Global callback for markers_data.js
  window.onObsMarkersUpdate = function (data) {
    updateWithData(data);
  };

  // Poll markers_data.js via dynamic script element (bypasses Chromium file:/// CORS restrictions)
  function pollLiveFile() {
    const oldScript = document.getElementById('obs-marker-data-tag');
    if (oldScript) {
      oldScript.remove();
    }

    const script = document.createElement('script');
    script.id = 'obs-marker-data-tag';
    script.src = `markers_data.js?_=${Date.now()}`;
    script.onload = () => {
      if (window.__OBS_MARKERS_DATA__) {
        updateWithData(window.__OBS_MARKERS_DATA__);
      }
    };
    script.onerror = async () => {
      // Fallback: try direct fetch if file is served via http/localhost
      try {
        const res = await fetch(`markers_live.json?_=${Date.now()}`, { cache: 'no-store' });
        if (res.ok) {
          const json = await res.json();
          updateWithData(json);
        }
      } catch (_) {}
    };
    document.head.appendChild(script);
  }

  // Poll every 1000ms
  setInterval(pollLiveFile, 1000);

  // Initial check if markers_data.js was loaded on page start
  if (window.__OBS_MARKERS_DATA__) {
    updateWithData(window.__OBS_MARKERS_DATA__);
  } else {
    pollLiveFile();
  }

  // Export Formats Generator
  function generateExport(format) {
    const title = elStreamTitle.value.trim() || 'My Stream';
    const dateStr = new Date().toISOString().split('T')[0];

    if (format === 'youtube') {
      let out = `00:00 Stream Start\n`;
      state.markers.forEach((m) => {
        const note = m.note || m.tag || 'Highlight';
        out += `${m.timestamp} ${note}\n`;
      });
      return { content: out, filename: `${title}_${dateStr}_youtube_chapters.txt` };
    }

    if (format === 'davinci') {
      let out = `Marker Type,Timecode,Duration,Name,Description\n`;
      state.markers.forEach((m, idx) => {
        const name = m.tag || `Highlight #${idx + 1}`;
        const desc = m.note || '';
        out += `Blue,${m.timestamp}:00,00:00:20:00,"${name}","${desc}"\n`;
      });
      return { content: out, filename: `${title}_${dateStr}_davinci_markers.csv` };
    }

    if (format === 'premiere') {
      let out = `TITLE: ${title} Markers\n`;
      state.markers.forEach((m, idx) => {
        out += `${idx + 1}  001  V  C  ${m.start_time}:00 ${m.timestamp}:00 ${m.start_time}:00 ${m.timestamp}:00\n`;
        out += ` |M: ${m.tag} |D: ${m.note || 'Clip'}\n\n`;
      });
      return { content: out, filename: `${title}_${dateStr}_premiere.edl` };
    }

    // Default Standard TXT
    let out = `================================================================\n`;
    out += `STREAM HIGHLIGHT MARKERS: ${title}\n`;
    out += `Export Date: ${new Date().toLocaleString()}\n`;
    out += `Total Markers: ${state.markers.length}\n`;
    out += `================================================================\n\n`;

    state.markers.forEach((m, idx) => {
      const note = m.note ? ` - ${m.note}` : '';
      out += `[#${idx + 1}] ${m.timestamp} (Clip: ${m.start_time} -> ${m.timestamp}) [${m.tag}]${note}\n`;
    });

    return { content: out, filename: `${title}_${dateStr}_markers.txt` };
  }

  function downloadTextFile(content, filename) {
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast(`Saved ${filename}!`);
  }

  // Event Listeners
  elBtnQuickMark.addEventListener('click', () => {
    addManualMarker();
  });

  elBtnSound.addEventListener('click', () => {
    state.soundEnabled = !state.soundEnabled;
    elSoundIconOn.classList.toggle('hidden', !state.soundEnabled);
    elSoundIconOff.classList.toggle('hidden', state.soundEnabled);
    if (state.soundEnabled) playChime();
  });

  elTagPresets.querySelectorAll('.chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      elTagPresets.querySelectorAll('.chip').forEach((c) => c.classList.remove('active'));
      chip.classList.add('active');
      state.activeTag = chip.getAttribute('data-tag');
    });
  });

  elBtnClearAll.addEventListener('click', () => {
    if (state.markers.length === 0) return;
    if (confirm('Clear all markers in this session?')) {
      state.markers.forEach((m) => deletedMarkerIds.add(m.id));
      persistDeletedIds();
      state.markers = [];
      renderMarkers();
      showToast('Cleared all markers');
    }
  });

  elBtnExportTxt.addEventListener('click', () => {
    if (state.markers.length === 0) {
      showToast('No markers to save yet');
      return;
    }
    const { content, filename } = generateExport('txt');
    downloadTextFile(content, filename);
  });

  elBtnCopy.addEventListener('click', async () => {
    if (state.markers.length === 0) {
      showToast('No markers to copy yet');
      return;
    }
    const { content } = generateExport('txt');
    try {
      await navigator.clipboard.writeText(content);
      showToast('Copied markers to clipboard!');
    } catch (e) {
      showToast('Error copying to clipboard');
    }
  });

  elBtnExportMore.addEventListener('click', (e) => {
    e.stopPropagation();
    elExportDropdown.classList.toggle('show');
  });

  document.addEventListener('click', () => {
    elExportDropdown.classList.remove('show');
  });

  elExportDropdown.querySelectorAll('.dropdown-item').forEach((item) => {
    item.addEventListener('click', (e) => {
      e.stopPropagation();
      elExportDropdown.classList.remove('show');
      if (state.markers.length === 0) {
        showToast('No markers to export yet');
        return;
      }
      const format = item.getAttribute('data-format');
      const { content, filename } = generateExport(format);
      downloadTextFile(content, filename);
    });
  });

  // Title input listener
  elStreamTitle.addEventListener('input', (e) => {
    state.streamTitle = e.target.value.trim() || 'My Stream';
  });

  // Delegated event listener for note edits in marker cards
  elMarkersList.addEventListener('input', (e) => {
    if (e.target && e.target.classList.contains('marker-note-input')) {
      const id = parseInt(e.target.getAttribute('data-id'), 10);
      const item = state.markers.find((x) => x.id === id);
      if (item) item.note = e.target.value;
    }
  });

  // Delegated event listener for deleting individual marker cards
  elMarkersList.addEventListener('click', (e) => {
    const btn = e.target.closest('.btn-card-del');
    if (btn) {
      const id = parseInt(btn.getAttribute('data-id'), 10);
      deletedMarkerIds.add(id);
      persistDeletedIds();
      state.markers = state.markers.filter((x) => x.id !== id);
      renderMarkers();
      showToast('Marker removed');
    }
  });

  // Initial render
  renderMarkers();
})();
