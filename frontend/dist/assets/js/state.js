/* state.js — store nhỏ gọn kiểu Redux-lite + debounce persist về backend */
(function () {
  "use strict";
  const { bridge } = window.HC;

  const state = {
    // nhập liệu
    text: "",
    // giọng & engine
    voices: [],
    voiceId: "Adam",
    enginePref: "auto",
    // PATCH FIX46: nhân bản giọng (runtime only, không persist)
    refCloneOn: false,
    refAudioPath: "",
    // thông số
    speed: 1.0,
    pitch: 0,
    volume: 0.9,
    // theme
    themeMode: "auto",           // auto | light | dark
    isDarkWin: false,            // trạng thái registry Windows (poll)
    manualOverride: false,       // người dùng đã bấm nút đổi theme chưa
    // runtime
    appState: null,
    currentJob: null,            // jobID đang chạy synth
    jobBusy: false,
    lastFinishedJob: null,
    playing: false,
    paused: false,
    progressPct: 0,
    stageLabel: "Sẵn sàng",
    etaSec: null,
    durationSec: null,
    cursorMs: 0,
    totalMs: 0,
    // download wizard
    dlVisible: false,
    dlRunning: false,
  };

  const subs = new Set();
  function emit(keys) {
    subs.forEach((cb) => cb(state, keys));
  }

  const actions = {
    patch(partial) {
      Object.assign(state, partial);
      emit(Object.keys(partial));
    },
    async hydrate() {
      const [appState, settings, voices] = await Promise.all([
        bridge.GetAppState(),
        safeGet(() => bridge.GetSettings(), null),
        bridge.ListVoices(),
      ]);
      state.appState = appState;
      if (settings) {
        state.voiceId = settings.voiceId || state.voiceId;
        state.enginePref = settings.enginePref || state.enginePref;
        state.speed = clamp(settings.speed ?? state.speed, .5, 2);
        state.pitch = clamp(settings.pitch ?? state.pitch, -12, 12);
        state.volume = clamp(settings.volume ?? state.volume, 0, 1);
        state.themeMode = settings.themeMode || "auto";
      }
      state.isDarkWin = appState.isDarkWin;
      state.voices = voices;
      // nếu giọng đã lưu không còn trong list (vd SAPI bị gỡ) → fallback Adam
      if (!voices.some((v) => v.id === state.voiceId)) {
        state.voiceId = voices[0]?.id || "Adam";
      }
      emit(["appState", "voiceId", "enginePref", "speed", "pitch", "volume",
            "themeMode", "isDarkWin", "voices"]);
    },
    saveDebounced() {
      clearTimeout(actions._t);
      actions._t = setTimeout(() => {
        bridge.SaveSettings({
          themeMode: state.themeMode,
          voiceId: state.voiceId,
          enginePref: state.enginePref,
          speed: state.speed,
          pitch: state.pitch,
          volume: state.volume,
          outDir: state.appState?.exportsDir || "",
          updatedAt: new Date().toISOString(),
        });
      }, 450);
    },
  };

  function safeGet(fn, dflt) {
    try { return fn(); } catch { return dflt; }
  }
  function clamp(v, a, b) {
    return Math.min(b, Math.max(a, Number(v) || 0));
  }

  window.HC.state = state;
  window.HC.actions = actions;
  window.HC.subscribe = (fn) => { subs.add(fn); fn(state, []); };
})();
