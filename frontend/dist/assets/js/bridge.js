/* ════════════════════════════════════════════════════════════
   bridge.js — Lớp giao tiếp frontend ↔ backend (Wails Bind/Bridge).
   Tự nhận diện môi trường:
     • Trong app Wails: dùng window.go.backend.App + window.runtime.EventsOn
     • Mở trực tiếp bằng trình duyệt: MockBackend mô phỏng toàn bộ pipeline
       (kèm WebAudio beep) để chốt thiết kế mà KHÔNG cần compile Go.
   Hợp đồng Promise/event giống hệt nhau ở cả hai chế độ.
   ════════════════════════════════════════════════════════════ */
(function () {
  "use strict";

  /* PATCH run #31: Wails bind theo TÊN PACKAGE Go — package main sẽ thành
     window.go.main.App, package backend thành window.go.backend.App.
     Chỉ thử một đường dẫn duy nhất là nguyên nhân app rơi vào chế độ MOCK
     dù chạy đúng trong Wails (log: bridge.mode=mock). Chọn đường dẫn nào
     tồn tại và có method thật mới tính là wails. */
  function resolveApi() {
    try {
      const g = window.go || {};
      const cand = (g.backend && g.backend.App) || (g.main && g.main.App) || null;
      return (cand && typeof cand.GetAppState === "function") ? cand : null;
    } catch (e) { return null; }
  }
  const hasWails = typeof window !== "undefined" && !!resolveApi();

  /* ---------------- Event Bus chung ---------------- */
  const listeners = new Map();
  const Bus = {
    on(event, cb) {
      if (!listeners.has(event)) listeners.set(event, new Set());
      listeners.get(event).add(cb);
      return () => Bus.off(event, cb);
    },
    off(event, cb) { listeners.get(event)?.delete(cb); },
    emitLocal(event, payload) {
      listeners.get(event)?.forEach((cb) => {
        try { cb(payload); } catch (e) { console.error(e); }
      });
    },
  };

  /* ---------------- Bridge thật (Wails) ---------------- */
  function createRealBridge() {
    const api = resolveApi(); // PATCH run #31: dùng đường dẫn đã resolve, không hard-code
    // Phản chiếu event Wails → Bus nội bộ
    ["hcstudio:job", "hcstudio:play", "hcstudio:modeldl", "hcstudio:toast", "hcstudio:transport"]
      .forEach((evt) => {
        if (window.runtime && window.runtime.EventsOn) {
          window.runtime.EventsOn(evt, (data) => Bus.emitLocal(evt, data));
        }
      });

    return {
      mode: "wails",
      bus: Bus,
      GetAppState: () => api.GetAppState(),
      ListVoices: () => api.ListVoices(),
      GetSettings: () => api.GetSettings(),
      SaveSettings: (s) => api.SaveSettings(s),
      Synthesize: (req) => api.Synthesize(req),
      PickRefAudio: () => api.PickRefAudio ? api.PickRefAudio() : Promise.resolve(""),
      PlayJob: (id) => api.PlayJob(id),
      PauseToggle: () => api.PauseToggle(),
      StopAll: () => api.StopAll(),
      ExportAudio: (job, fmt, path) => api.ExportAudio(job, fmt, path),
      PickSavePath: (name) => api.PickSavePath(name, ""),
      CancelModelDownload: () => api.CancelModelDownload(),
      DownloadNeuralAssets: () => api.DownloadNeuralAssets(),
      ImportOfflinePackage: () => api.ImportOfflinePackage ? api.ImportOfflinePackage() : Promise.resolve(""),
      OpenFolder: (w) => api.OpenFolder(w),
      WindowAction: (cmd) => api.WindowAction(cmd),
      DetectWinTheme: () => api.DetectWinTheme(),
    };
  }

  /* ---------------- Mock bridge (browser preview) ---------------- */

  // Catalog 25 giọng VieNeu chuẩn — nguồn truth: voices_v3_turbo.json @fa2b1afa (FIX46)
  const MOCK_NEURAL = [
    ["Adam", "male", "Nam", "Nam · Nam · Giọng đọc tự nhiên"],
    ["Phạm Tuyên", "male", "Bắc", "Nam · Bắc · Phong cách tự nhiên"],
    ["Minh Đức", "male", "Bắc", "Nam · Bắc · Phong cách tin tức"],
    ["Thanh Bình", "male", "Bắc", "Nam · Bắc · Phong cách kể chuyện"],
    ["Ngọc Huyền", "female", "Bắc", "Nữ · Bắc · Giọng đọc tự nhiên"],
    ["Trúc Ly", "female", "Bắc", "Nữ · Bắc · Phong cách tự nhiên"],
    ["Đoan Trang", "female", "Bắc", "Nữ · Bắc · Phong cách tự nhiên"],
    ["Ngọc Linh", "female", "Bắc", "Nữ · Bắc · Phong cách kể chuyện"],
    ["Mai Anh", "female", "Bắc", "Nữ · Bắc · Phong cách tin tức"],
    ["Quỳnh Anh", "female", "Bắc", "Nữ · Bắc · Phong cách đọc truyện"],
    ["Quang Sơn", "male", "Trung", "Nam · Trung · Phong cách tự nhiên"],
    ["Ngọc Trân", "female", "Trung", "Nữ · Trung · Phong cách tự nhiên"],
    ["Xuân Vĩnh", "male", "Nam", "Nam · Nam · Phong cách tự nhiên"],
    ["Thái Sơn", "male", "Nam", "Nam · Nam · Phong cách kể chuyện"],
    ["Minh Triết", "male", "Nam", "Nam · Nam · Phong cách tin tức"],
    ["Đức Trí", "male", "Nam", "Nam · Nam · Phong cách đọc truyện"],
    ["Thục Đoan", "female", "Nam", "Nữ · Nam · Phong cách kể chuyện"],
    ["Thùy Dung", "female", "Nam", "Nữ · Nam · Phong cách tin tức"],
    ["Mỹ Duyên", "female", "Nam", "Nữ · Nam · Phong cách đọc truyện"],
    ["Kim Thanh", "female", "Nam", "Nữ · Nam · Phong cách đọc truyện"],
    ["Adam bựa", "male", "Bắc", "Nam · Bắc · Phong cách tự nhiên (mới)"],
    ["Anh Khôi", "male", "Bắc", "Nam · Bắc · Phong cách kể chuyện (mới)"],
    ["Minh Quân Pro", "male", "Bắc", "Nam · Bắc · Phong cách tự nhiên (mới)"],
    ["Thiền Tâm Đức", "male", "Bắc", "Nam · Bắc · Phong cách kể chuyện (mới)"],
    ["Mạnh Dũng", "male", "Bắc", "Nam · Bắc · Phong cách tự nhiên (mới)"],
  ].map(([name, gender, region, desc], i) => ({
    id: name, name, gender, region,
    style: desc.includes("tin tức") ? "tin_tuc" : desc.includes("truyện") || desc.includes("chuyện") ? "doc_truyen" : "tu_nhien",
    engine: "neural",
    description: desc,
    available: true,
    rank: i,
  }));

  const MOCK_SAPI = [
    { id: "sapi:Microsoft An - Vietnamese", name: "Microsoft An – Vietnamese", gender: "unknown",
      region: "Hệ thống", style: "sapi", engine: "sapi",
      description: "Giọng hệ thống Windows · Microsoft An", available: true, rank: 1000 },
    { id: "sapi:Microsoft David Desktop", name: "Microsoft David Desktop", gender: "male",
      region: "Hệ thống", style: "sapi", engine: "sapi",
      description: "Giọng hệ thống Windows · Microsoft David", available: true, rank: 1001 },
  ];

  function createMockBridge() {
    console.info("[HCStudio] CHẾ ĐỘ PREVIEW TRÌNH DUYỆT — mọi dữ liệu là giả lập.");
    let dark = window.matchMedia?.("(prefers-color-scheme: dark)").matches ?? false;
    let jobSeq = 0;
    let audioCtx = null;
    let playing = false;

    const beep = (ms = 260) => {
      try {
        audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
        const o = audioCtx.createOscillator(), g = audioCtx.createGain();
        o.frequency.value = 440 * Math.pow(2, ((jobSeq % 3) - 1) / 12);
        g.gain.value = .07;
        o.connect(g).connect(audioCtx.destination);
        o.start();
        g.gain.exponentialRampToValueAtTime(1e-4, audioCtx.currentTime + ms / 1000);
        o.stop(audioCtx.currentTime + ms / 1000);
      } catch (_) { /* không có audio cũng kệ */ }
    };

    return {
      mode: "mock",
      bus: Bus,
      async GetAppState() {
        return {
          version: "5.0.0-preview",
          isDarkWin: dark,
          neuralLinked: true,
          neuralReady: true,
          missingFiles: [],
          modelDir: "%LOCALAPPDATA%\\HCStudio\\models\\vieneu-v3-turbo",
          voiceCountHint: 20,
          cpuThreads: navigator.hardwareConcurrency || 8,
          exportsDir: "%USERPROFILE%\\Documents\\HCStudio Exports",
        };
      },
      async ListVoices() { return [...MOCK_NEURAL, ...MOCK_SAPI]; },
      async GetSettings() {
        return { themeMode: "auto", voiceId: "Adam", enginePref: "auto",
                 speed: 1, pitch: 0, volume: .9, outDir: "", updatedAt: "" };
      },
      async SaveSettings() {},
      async Synthesize(req) {
        const id = `job-${++jobSeq}`;
        setTimeout(() => Bus.emitLocal("hcstudio:job", { id, state: "splitting", pct: 1, message: "Đang tách câu…" }), 30);

        const len = Math.max(req.text.length, 20);
        const chunks = Math.min(9, Math.ceil(len / 220)) + 1;
        let step = 0;

        const tick = () => {
          if (++step > chunks) {
            Bus.emitLocal("hcstudio:job", { id, state: "dsp", pct: 95, message: "Tinh chỉnh DSP…" });
            setTimeout(() => {
              const durationSec = Math.min(len / 14, 90);
              Bus.emitLocal("hcstudio:job", { id, state: "done", pct: 100, message: "Hoàn tất", durationSec });
              if (req.autoPlay) fakePlayback(id, durationSec);
            }, 420);
            return;
          }
          Bus.emitLocal("hcstudio:job", {
            id, state: "synthesizing",
            pct: 8 + (step / chunks) * 84,
            message: `Câu ${step}/${chunks} · giọng ${req.voiceId}`,
            etaSec: (chunks - step) * .55,
            durationSec: .6,
          });
          setTimeout(tick, 340 + Math.random() * 420); // luôn lên lịch — nhánh kế tiếp xử lý done
        };
        setTimeout(tick, 300);
        return id;
      },
      async PlayJob(id) { fakePlayback(id, 8.2); },
      async PauseToggle() {
        playing = !playing;
        Bus.emitLocal("hcstudio:play", { playing, jobId: "job-1" });
        Bus.emitLocal("hcstudio:transport", { playing });
        return playing;
      },
      async StopAll() {
        playing = false;
        Bus.emitLocal("hcstudio:play", { playing: false });
        Bus.emitLocal("hcstudio:transport", { playing: false });
      },
      async PickSavePath(defaultName) {
        return prompt("Chọn nơi lưu (mô phỏng hộp thoại native):", defaultName || "hcstudio.wav") || "";
      },
      async ExportAudio(jobId, format, path) {
        // render WAV nhỏ chứa beep để người xem thấy flow tải file thật
        try {
          const sr = 22050, dur = 1.1, n = sr * dur;
          const buf = new ArrayBuffer(44 + n * 2), v = new DataView(buf);
          const ws = (o, s) => [...s].forEach((c, i) => v.setUint8(o + i, c.charCodeAt(0)));
          ws(0, "RIFF"); v.setUint32(4, 36 + n * 2, true); ws(8, "WAVE");
          ws(12, "fmt "); v.setUint32(16, 16, true); v.setUint16(20, 1, true);
          v.setUint16(22, 1, true); v.setUint32(24, sr, true); v.setUint32(28, sr * 2, true);
          v.setUint16(32, 2, true); v.setUint16(34, 16, true);
          ws(36, "data"); v.setUint32(40, n * 2, true);
          for (let i = 0; i < n; i++) {
            const t = i / sr;
            v.setInt16(44 + i * 2, Math.sin(t * 550) * Math.exp(-3 * t) * 22000, true);
          }
          const a = document.createElement("a");
          a.href = URL.createObjectURL(new Blob([buf], { type: "audio/wav" }));
          a.download = path.split(/[\\/]/).pop() || ("hcstudio." + format);
          a.click();
        } catch (_) {}
        Bus.emitLocal("hcstudio:toast", {
          level: "success", title: "Đã xuất audio (preview)",
          message: `${format.toUpperCase()} đang được tải về từ trình duyệt.`,
        });
      },
      async CancelModelDownload() {},
      async DownloadNeuralAssets() { simulateDownload(); },
      async ImportOfflinePackage() {
        Bus.emitLocal("hcstudio:toast", {
          level: "info", title: "Nhập gói ZIP (preview)",
          message: "Tính năng nhập gói ZIP chỉ khả dụng trong bản Windows.",
        });
        return "";
      },
      async OpenFolder() {}, 
      WindowAction(cmd) { alert(`WindowAction: ${cmd} (chỉ có tác dụng trong bản Windows)`); },
      DetectWinTheme: async () => dark,
    };

    function fakePlayback(id, totalSec) {
      playing = true;
      Bus.emitLocal("hcstudio:transport", { playing: true, jobId: id });
      Bus.emitLocal("hcstudio:play", { jobId: id, playing: true });
      beep();
      let t = 0;
      const iv = setInterval(() => {
        t += .25;
        if (!playing || t >= totalSec) {
          clearInterval(iv);
          Bus.emitLocal("hcstudio:play", { playing: false });
          Bus.emitLocal("hcstudio:transport", { playing: false });
          return;
        }
        Bus.emitLocal("hcstudio:play", {
          jobId: id, playing: true,
          cursorMs: t * 1000, totalMs: totalSec * 1000,
          pct: t / totalSec * 100,
        });
        if (Math.abs(t % 1.6) < .13) beep(180);
      }, 250);
    }

    function simulateDownload() {
      const files = [
        "voices_v3_turbo.json", "config.json", "tokenizer.json",
        "codec/moss_audio_tokenizer_encode.onnx", "…", "onnx/vieneu_backbone_shared.data",
      ];
      let done = 0;
      const iv = setInterval(() => {
        done += 3 + Math.random() * 7;
        if (done >= 100) {
          done = 100; clearInterval(iv);
          Bus.emitLocal("hcstudio:modeldl", { state: "done", pct: 100, bytesDone: 1082734080, bytesTotal: 1082734080 });
          return;
        }
        Bus.emitLocal("hcstudio:modeldl", {
          state: "running", pct: done,
          currentFile: files[Math.floor(done / 100 * files.length)] || files[5],
          fileIdx: Math.min(files.length, 1 + Math.floor(done / 100 * files.length)),
          totalFiles: files.length,
          bytesDone: 10.8e9 * done / 100 | 0, bytesTotal: 10.8e9 | 0,
        });
      }, 240);
    }
  }

  /* ---------------- Public surface ---------------- */
  const bridge = hasWails ? createRealBridge() : createMockBridge();
  // KHÔNG freeze: state.js / ui.js gắn thêm namespace vào HC sau khi load.
  window.HC = { bridge };
  window.HC.isWails = !!hasWails;
})();
