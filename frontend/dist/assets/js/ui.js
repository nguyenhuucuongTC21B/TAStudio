/* ui.js — toàn bộ thao tác DOM: dropdown giọng, sliders, transport, toasts… */
(function () {
  "use strict";
  const { bridge, state, actions, subscribe } = window.HC;

  const $ = (sel) => document.querySelector(sel);
  const els = {};
  [
    "engine-pill", "btn-theme", "btn-models", "text-input", "char-count", "eta-chip",
    "voice-dropdown", "voice-toggle", "voice-panel", "voice-search", "voice-list",
    "voice-avatar", "voice-current-name", "voice-current-desc", "voice-count-chip",
    "sl-speed", "sl-pitch", "sl-volume", "out-speed", "out-pitch", "out-volume",
    "progress-fill", "stage-label", "pct-label", "clock-label",
    "btn-play", "btn-stop", "btn-export-wav", "btn-export-mp3", "btn-paste", "btn-clear",
    "setup-overlay", "wiz-dl", "wiz-skip", "dl-progress", "dl-fill", "dl-file",
    "dl-files-idx", "dl-bytes", "dl-pct", "wiz-size", "toasts",
    "engine-segmented",
    // PATCH FIX48: nhập gói ZIP weights từ nguồn riêng
    "wiz-import",
    // PATCH FIX46: nhân bản giọng
    "ref-clone-check", "ref-clone-body", "ref-clone-pick", "ref-clone-name",
  ].forEach((id) => { els[id] = document.getElementById(id); });

  /* ---------- helpers ---------- */
  const fmtTime = (ms) => {
    const total = Math.max(0, Math.round(ms / 1000));
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
  };
  const setProgress = (pct) => {
    pct = Math.max(0, Math.min(100, pct || 0));
    els["progress-fill"].style.setProperty("--w", pct + "%");
    els["progress-fill"].classList.toggle("active", pct > 0 && pct < 100);
    els["pct-label"].textContent = Math.round(pct) + "%";
  };

  /* ---------- THEME ---------- */
  function applyTheme() {
    let dark;
    if (state.themeMode === "auto") dark = state.isDarkWin;
    else dark = state.themeMode === "dark";
    document.documentElement.classList.toggle("dark", dark);
    renderIconsFor(els["btn-theme"], state.themeMode === "auto"
      ? (dark ? ICONS.moon : ICONS.sun)
      : (dark ? ICONS.moon : ICONS.sun));
  }
  const renderIconsFor = (el, svgHtml) => { if (el) el.innerHTML = svgHtml; };

  /* ---------- VOICE DROPDOWN ---------- */
  function voiceAvatarClass(v) {
    return "v-avatar " + (v.gender === "female" ? "female" : v.gender === "male" ? "male" : "unknown");
  }
  function renderVoiceList() {
    const q = (els["voice-search"].value || "").trim().toLowerCase();
    const list = els["voice-list"];
    list.innerHTML = "";

    // group theo region đúng thứ tự Bắc → Trung → Nam → Hệ thống
    const order = ["Bắc", "Trung", "Nam", "Hệ thống"];
    const groups = new Map();
    state.voices.forEach((v) => {
      if (!groups.has(v.region)) groups.set(v.region, []);
      groups.get(v.region).push(v);
    });

    [...groups.entries()]
      .sort((a, b) => (order.indexOf(a[0]) + 99) % 999 - (order.indexOf(b[0]) + 99) % 999)
      .forEach(([region, voices]) => {
        const matched = voices.filter((v) =>
          !q || v.name.toLowerCase().includes(q) ||
          v.description.toLowerCase().includes(q));
        if (!matched.length) return;

        const head = document.createElement("div");
        head.className = "region-head";
        head.textContent = region === "Hệ thống" ? "GIỌNG HỆ THỐNG · SAPI5" : `MIỀN ${region.toUpperCase()}`;
        list.appendChild(head);

        matched.forEach((v) => {
          const btn = document.createElement("button");
          btn.type = "button";
          btn.className = "voice-item" + (v.id === state.voiceId ? " selected" : "")
            + (v.available ? "" : " badge-unavailable");
          btn.innerHTML = `
            <span class="${voiceAvatarClass(v)}">${v.name[0]}</span>
            <span class="vi-meta"><b>${v.name}</b><small>${v.description}</small></span>
            ${v.engine === "neural" ? '<span class="badge-engine neural">NEURAL</span>'
                                    : '<span class="badge-engine">SAPI</span>'}`;
          btn.addEventListener("click", () => selectVoice(v.id));
          list.appendChild(btn);
        });
      });

    els["voice-count-chip"].textContent =
      `${state.voices.filter((v) => v.available).length} giọng khả dụng`;
  }

  function syncVoiceSummary() {
    const v = state.voices.find((x) => x.id === state.voiceId);
    if (!v) return;
    els["voice-current-name"].textContent = v.name;
    els["voice-current-desc"].textContent = v.description;
    els["voice-avatar"].className = voiceAvatarClass(v);
    els["voice-avatar"].textContent = v.name[0];
    renderVoiceList();
  }

  function selectVoice(id) {
    actions.patch({ voiceId: id });
    closeDropdown();
    actions.saveDebounced();
  }
  function closeDropdown() {
    els["voice-dropdown"].classList.remove("open");
  }
  function wireDropdown() {
    els["voice-toggle"].addEventListener("click", (e) => {
      e.stopPropagation();
      const open = !els["voice-dropdown"].classList.contains("open");
      els["voice-dropdown"].classList.toggle("open", open);
      if (open) {
        renderVoiceList();
        setTimeout(() => els["voice-search"].focus(), 60);
      }
    });
    els["voice-search"].addEventListener("input", renderVoiceList);
    els["voice-panel"].addEventListener("click", (e) => e.stopPropagation());
    document.addEventListener("click", closeDropdown);
    document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeDropdown(); });
  }

  /* ---------- ENGINE SEGMENTED ---------- */
  function renderEngineSeg() {
    els["engine-segmented"].querySelectorAll(".seg-btn").forEach((b) =>
      b.classList.toggle("active", b.dataset.engine === state.enginePref));
  }
  function wireEngineSeg() {
    els["engine-segmented"].addEventListener("click", (e) => {
      const b = e.target.closest(".seg-btn");
      if (!b) return;
      actions.patch({ enginePref: b.dataset.engine });
      renderEngineSeg();
      actions.saveDebounced();
    });
  }

  /* ---------- SLIDERS ---------- */
  function sliderFill(input) {
    const min = parseFloat(input.min), max = parseFloat(input.max), v = parseFloat(input.value);
    input.style.setProperty("--fill-pct", ((v - min) / (max - min) * 100) + "%");
  }
  function renderSliders() {
    [els["sl-speed"], els["sl-pitch"], els["sl-volume"]].forEach(sliderFill);

    els["sl-speed"].value = state.speed;
    els["sl-pitch"].value = state.pitch;
    els["sl-volume"].value = Math.round(state.volume * 100);

    els["out-speed"].textContent = state.speed.toFixed(2).replace(/0$/, "") + "×";
    els["out-pitch"].textContent =
      (state.pitch > 0 ? "+" : "") + Number(state.pitch).toFixed(1).replace(/\.0$/, "") +
      " semitone";
    els["out-volume"].textContent = Math.round(state.volume * 100) + "%";

    [els["sl-speed"], els["sl-pitch"], els["sl-volume"]].forEach(sliderFill);
  }
  function wireSliders() {
    els["sl-speed"].addEventListener("input", () => {
      actions.patch({ speed: parseFloat(els["sl-speed"].value) });
      renderSliders(); actions.saveDebounced();
    });
    els["sl-pitch"].addEventListener("input", () => {
      actions.patch({ pitch: parseFloat(els["sl-pitch"].value) });
      renderSliders(); actions.saveDebounced();
    });
    els["sl-volume"].addEventListener("input", () => {
      actions.patch({ volume: parseFloat(els["sl-volume"].value) / 100 });
      renderSliders(); actions.saveDebounced();
    });
  }

  /* ---------- EDITOR ---------- */
  function updateCounter() {
    const n = [...state.text].length; // đếm rune tiếng Việt chuẩn
    els["char-count"].textContent = n.toLocaleString("vi-VN") + " ký tự";
    // dự báo thời lượng: ~14–15 ký tự/giây với tốc độ 1×
    const etaSec = Math.round(n / 15 / Math.max(state.speed, .1));
    els["eta-chip"].hidden = n < 30;
    els["eta-chip"].textContent =
      n >= 30 ? `≈ ${fmtTime(etaSec * 1000)} audio` : "";
  }
  function wireEditor() {
    els["text-input"].addEventListener("input", () => {
      state.text = els["text-input"].value;
      updateCounter();
    });
    els["btn-clear"].addEventListener("click", () => {
      els["text-input"].value = "";
      state.text = "";
      updateCounter();
      els["text-input"].focus();
    });
    els["btn-paste"].addEventListener("click", async () => {
      try {
        const txt = await navigator.clipboard.readText();
        if (txt) {
          els["text-input"].value += txt;
          state.text = els["text-input"].value;
          updateCounter();
        }
      } catch { toast("warn", "Không đọc được clipboard", "Trình duyệt chặn quyền — dán bằng Ctrl+V nhé."); }
    });
    els["text-input"].addEventListener("keydown", (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
        e.preventDefault();
        window.HC.ui.playRequested();
      }
    });
  }

  /* ---------- TRANSPORT ---------- */
  function renderTransport() {
    const busy = state.jobBusy || state.playing;
    els["btn-play"].disabled = false;
    els["btn-play"].querySelector(".ico-play").hidden = state.playing && !state.paused;
    els["btn-play"].querySelector(".ico-pause").hidden = !(state.playing && !state.paused);
    els["btn-stop"].disabled = !busy;
    els["btn-export-wav"].disabled = !state.lastFinishedJob;
    els["btn-export-mp3"].disabled = !state.lastFinishedJob;

    setProgress(state.playing
      ? (state.totalMs ? state.cursorMs / state.totalMs * 100 : 0)
      : state.progressPct);
    els["stage-label"].textContent = state.stageLabel;

    if (state.playing && state.totalMs > 0) {
      els["clock-label"].textContent =
        `${fmtTime(state.cursorMs)} / ${fmtTime(state.totalMs)}`;
    } else if (state.durationSec > 0) {
      els["clock-label"].textContent = `0:00 / ${fmtTime(state.durationSec * 1000)}`;
    } else {
      els["clock-label"].textContent = "0:00 / 0:00";
    }
  }

  /* ---------- TOASTS ---------- */
  function toast(level, title, message = "", timeout = 4200) {
    const div = document.createElement("div");
    div.className = `toast ${level}`;
    const iconMap = { success: ICONS.check, warn: ICONS.warn, error: ICONS.errorx, info: ICONS.info };
    div.innerHTML = `${iconMap[level] || ICONS.info}
      <div><b>${escapeHtml(title)}</b>${message ? `<small>${escapeHtml(message)}</small>` : ""}</div>`;
    els["toasts"].appendChild(div);
    setTimeout(() => {
      div.classList.add("leaving");
      setTimeout(() => div.remove(), 240);
    }, timeout);
  }
  function escapeHtml(s) {
    return s.replace(/[&<>"']/g, (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  /* ---------- WIZARD ---------- */
  function showWizard(show) {
    els["setup-overlay"].hidden = !show;
  }
  function renderDownload(e) {
    if (!els["setup-overlay"].hidden || state.dlRunning) {
      els["dl-progress"].hidden = !(e && (e.state === "running"));
      if (e && e.state !== undefined) {
        // PATCH run #31: kẹp pct 0..100 phòng backend cũ gửi giá trị thô
        // (đã gặp 14227792400% khi SizeHint chưa được nhúng vào manifest).
        const pct = Math.max(0, Math.min(100, e.pct ?? 0));
        els["dl-fill"].style.setProperty("--w", pct + "%");
        if (e.currentFile) els["dl-file"].textContent = e.currentFile.split("/").pop();
        if (e.fileIdx) els["dl-files-idx"].textContent = `${e.fileIdx}/${e.totalFiles}`;
        if (e.bytesDone != null)
          els["dl-bytes"].textContent = `${fmtBytes(e.bytesDone)} / ${fmtBytes(e.bytesTotal)}`;
        els["dl-pct"].textContent = Math.round(pct) + "%";
      }
    }
    if (e?.state === "done") {
      state.dlRunning = false;
      refreshAppStateThenVoices();
      showWizard(false);
    } else if (e?.state === "error") {
      state.dlRunning = false;
      toast("error", "Tải mô hình lỗi", e.message || "");
      els["wiz-dl"].disabled = false;
    } else if (e?.state === "cancelled") {
      state.dlRunning = false;
      els["wiz-dl"].disabled = false;
    }
  }
  const fmtBytes = (b) => {
    if (b >= 1073741824) return (b / 1073741824).toFixed(2) + " GB";
    if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB";
    if (b >= 1024) return (b / 1024).toFixed(1) + " KB";
    return b + " B";
  };
  async function refreshAppStateThenVoices() {
    await actions.hydrate();
  }
  function wireWizard() {
    els["wiz-dl"].addEventListener("click", async () => {
      els["wiz-dl"].disabled = true;
      state.dlRunning = true;
      await bridge.DownloadNeuralAssets();
    });
    // PATCH FIX48 — CHỦ QUYỀN NGUỒN: nhập gói ZIP weights từ nguồn riêng
    // (GitHub Release của chủ app, NAS, USB...) — không cần mạng.
    if (els["wiz-import"]) {
      els["wiz-import"].addEventListener("click", async () => {
        els["wiz-import"].disabled = true;
        try {
          const raw = await bridge.ImportOfflinePackage();
          let rep = null;
          try { rep = raw ? JSON.parse(raw) : null; } catch (_) {}
          if (!rep || !rep.message) {
            // người dùng đóng hộp thoại chọn file — im lặng
          } else if (rep.ok) {
            toast("success", "Đã nhập gói mô hình", rep.message, 6000);
            await refreshAppStateThenVoices();
            showWizard(false);
          } else {
            toast("error", "Nhập gói chưa hoàn tất", rep.message, 8000);
          }
        } finally {
          els["wiz-import"].disabled = false;
        }
      });
    }
    els["wiz-skip"].addEventListener("click", () => showWizard(false));
  }

  /* ---------- TITLEBAR ---------- */
  function wireTitlebar() {
    $("#btn-win-close").addEventListener("click", () => bridge.WindowAction("close"));
    $("#btn-win-min").addEventListener("click", () => bridge.WindowAction("min"));
    $("#btn-win-max").addEventListener("click", () => bridge.WindowAction("max"));
    els["btn-theme"].addEventListener("click", cycleTheme);
    els["btn-models"].addEventListener("click", () => bridge.OpenFolder("models"));
  }
  function cycleTheme() {
    // chu kỳ auto → light → dark → auto
    state.themeMode = state.themeMode === "auto" ? "light"
                    : state.themeMode === "light" ? "dark" : "auto";
    applyTheme();
    actions.saveDebounced();
    const label = { auto: "Tự động theo Windows", light: "Chế độ sáng", dark: "Chế độ tối" };
    toast("info", label[state.themeMode], "", 1600);
  }

  function renderEnginePill() {
    const pill = els["engine-pill"];
    const as = state.appState;
    if (!as) return;
    if (!as.neuralLinked) {
      pill.textContent = "LITE · SAPI5"; pill.className = "engine-pill offline";
    } else if (as.neuralReady) {
      pill.textContent = "NEURAL READY"; pill.className = "engine-pill ready";
    } else {
      pill.textContent = "THIẾU MÔ HÌNH"; pill.className = "engine-pill missing";
    }
  }

  /* ---------- EXPOSE ---------- */
  // PATCH FIX46: wiring nhân bản giọng — checkbox bật/tắt panel, nút chọn
  // file WAV qua dialog native; state chỉ runtime, không persist settings.
  function wireRefClone() {
    if (!els["ref-clone-check"]) return;
    els["ref-clone-check"].addEventListener("change", () => {
      const on = !!els["ref-clone-check"].checked;
      els["ref-clone-body"].style.display = on ? "block" : "none";
      if (on && !state.refAudioPath) {
        toast("info", "Nhân bản giọng",
          "Chọn một file WAV giọng mẫu 5–15 giây (nói rõ, ít tiếng ồn) để đọc thử.");
      }
      actions.patch({ refCloneOn: on });
    });
    els["ref-clone-pick"].addEventListener("click", () => {
      Promise.resolve(bridge.PickRefAudio()).then((path) => {
        if (!path) return;
        els["ref-clone-name"].textContent = path.split(/[\\/]/).pop();
        els["ref-clone-name"].title = path;
        actions.patch({ refAudioPath: path });
        toast("success", "Đã chọn file mẫu", path);
      }).catch(() => {});
    });
  }

  window.HC.ui = {
    init() {
      renderIcons(document);   // thay mọi i[data-ico]
      wireTitlebar();
      wireDropdown();
      wireEngineSeg();
      wireSliders();
      wireEditor();
      wireWizard();
      wireRefClone();

      bridge.bus.on("hcstudio:job", (j) => {
        if (j.state === "splitting" || j.state === "synthesizing" || j.state === "dsp") {
          actions.patch({ jobBusy: true, currentJob: j.id,
            progressPct: j.pct, stageLabel: j.message || j.state, etaSec: j.etaSec });
        } else if (j.state === "done") {
          actions.patch({ jobBusy: false, lastFinishedJob: j.id,
            progressPct: 100, stageLabel:
              `Hoàn tất · ${fmtTime((j.durationSec ?? 0) * 1000)}`,
            durationSec: j.durationSec });
          setTimeout(() => actions.patch({
            stageLabel: state.playing ? "Đang phát…" : "Sẵn sàng"
          }), 2600);
        } else if (j.state === "error") {
          actions.patch({ jobBusy: false, progressPct: 0,
            stageLabel: "Lỗi · xem thông báo", currentJob: null });
        } else if (j.state === "cancelled") {
          actions.patch({ jobBusy: false, progressPct: 0, stageLabel: "Đã huỷ" });
        }
      });
      bridge.bus.on("hcstudio:play", (p) => {
        actions.patch({
          playing: !!p.playing,
          cursorMs: p.cursorMs ?? state.cursorMs,
          totalMs: p.totalMs ?? state.totalMs,
          paused: false,
          stageLabel: p.playing ? "Đang phát…"
            : (state.jobBusy ? state.stageLabel : "Sẵn sàng"),
        });
      });
      bridge.bus.on("hcstudio:transport", (t) => {
        actions.patch({ playing: !!t.playing });
      });
      bridge.bus.on("hcstudio:toast", (t) => toast(t.level, t.title, t.message));
      bridge.bus.on("hcstudio:modeldl", renderDownload);
    },

    playRequested() {
      const text = els["text-input"].value.trim();
      if (state.playing) {
        // đang phát → pause/resume
        bridge.PauseToggle().then((pausedNow) => {
          actions.patch({ paused: pausedNow,
            stageLabel: pausedNow ? "Tạm dừng" : "Đang phát…" });
        });
        return;
      }
      if (!text) {
        toast("warn", "Chưa có văn bản", "Nhập hoặc dán nội dung trước khi phát nhé.");
        els["text-input"].focus();
        return;
      }
      state.text = text;
      // PATCH FIX46: nhân bản giọng — khi bật, bỏ voice preset và gửi path
      // file WAV mẫu; backend buộc neural + core dùng ref_audio_path.
      const useRef = state.refCloneOn && state.refAudioPath;
      bridge.Synthesize({
        text,
        voiceId: useRef ? "" : state.voiceId,
        engineOverride: useRef ? "neural" : state.enginePref,
        speed: state.speed,
        pitch: state.pitch,
        volume: state.volume,
        autoPlay: true,
        refAudioPath: useRef ? state.refAudioPath : "",
      }).then(() => actions.patch({ stageLabel: "Bắt đầu tổng hợp…", progressPct: 0 }));
    },

    stopRequested() {
      bridge.StopAll();
    },

    exportAudio(format) {
      const job = state.lastFinishedJob;
      if (!job) {
        toast("warn", "Chưa có bản ghi nào", "Hãy phát một đoạn văn bản trước đã.");
        return;
      }
      const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
      bridge.PickSavePath(`HCStudio_${stamp}.${format}`).then((path) => {
        if (!path) return;
        bridge.ExportAudio(job, format, path);
      });
    },
  };

  /* ---------- SUBSCRIBE → render loop duy nhất ---------- */
  subscribe((s, keys) => {
    if (keys.includes("isDarkWin") || keys.includes("themeMode")) applyTheme();
    if (keys.includes("voices") || keys.includes("voiceId")) syncVoiceSummary();
    if (keys.includes("enginePref")) renderEngineSeg();
    if (keys.includes("speed") || keys.includes("pitch") || keys.includes("volume")) renderSliders();
    if (keys.length === 0 || true) renderTransport();
    if (keys.includes("appState")) {
      renderEnginePill();
      // mở wizard lần đầu nếu neural thiếu và người dùng chưa quyết gì
      if (s.appState.neuralLinked && !s.appState.neuralReady && !window.HC._wizDismissed) {
        showWizard(true);
      }
    }
  });
})();
