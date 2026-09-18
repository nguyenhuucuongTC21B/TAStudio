/* main.js — bootstrap: hydrate state từ backend rồi khoá giao diện */
(function () {
  "use strict";
  const { bridge, actions } = window.HC;

  document.addEventListener("DOMContentLoaded", async () => {
    // Khởi động UI trước: wire titlebar/dropdown/sliders/bus subscriptions/icons
    window.HC.ui.init();

    // nút transport (gắn tại đây để trễ vòng deps UI 内部)
    document.getElementById("btn-play")
      .addEventListener("click", () => window.HC.ui.playRequested());
    document.getElementById("btn-stop")
      .addEventListener("click", () => window.HC.ui.stopRequested());
    document.getElementById("btn-export-wav")
      .addEventListener("click", () => window.HC.ui.exportAudio("wav"));
    document.getElementById("btn-export-mp3")
      .addEventListener("click", () => window.HC.ui.exportAudio("mp3"));

    // poll theme Windows mỗi 3s nếu đang auto (giống hành vi native apps)
    setInterval(async () => {
      try {
        const dark = await bridge.DetectWinTheme();
        if (window.HC.state.isDarkWin !== dark) {
          window.HC.actions.patch({ isDarkWin: dark });
        }
      } catch (_) {}
    }, 3000);

    await actions.hydrate();
    console.info(`[HCStudio] sẵn sàng · mode=${bridge.mode}`);
  });
})();
