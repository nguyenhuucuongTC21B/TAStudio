/* icons.js — bộ SVG inline (không CDN, giữ offline tuyệt đối) */
(function () {
  "use strict";
  const S = (paths, extra = "") =>
    `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" ${extra}>${paths}</svg>`;

  const st = 'stroke-linecap="round" stroke-linejoin="round"';
  const ICONS = {
    play:   S('<path d="M7 4.5v15l13-7.5z"/>'),
    pause:  S('<rect x="5.5" y="4.5" width="4.5" height="15" rx="1.4"/><rect x="14" y="4.5" width="4.5" height="15" rx="1.4"/>'),
    stop:   S('<rect x="5.5" y="5.5" width="13" height="13" rx="2.6"/>'),
    sun:    S(`<circle cx="12" cy="12" r="4.6"/><path d="M12 2v2.4M12 19.6V22M2 12h2.4M19.6 12H22M4.5 4.5l1.7 1.7M17.8 17.8l1.7 1.7M19.5 4.5l-1.7 1.7M6.2 17.8l-1.7 1.7" ${st}/>`, 'fill="none" stroke="currentColor"'),
    moon:   S('<path d="M21 13.2A9.1 9.1 0 1110.8 3a7.4 7.4 0 1010.2 10.2z"/>'),
    folder: S(`<path d="M3.5 6.5A2 2 0 015.5 4.5h4l2 2.5h7a2 2 0 012 2v8a2 2 0 01-2 2h-13a2 2 0 01-2-2z" ${st}/>`, 'fill="none" stroke="currentColor"'),
    paste:  S(`<rect x="7" y="4" width="10" height="17" rx="2.2"/><path d="M9.6 4a2.4 2.4 0 014.8 0M9.2 11h5.6M9.2 14.6h3.4" ${st}/>`, 'fill="none" stroke="currentColor"'),
    trash:  S(`<path d="M4.5 7h15M9.5 7V5.2A1.2 1.2 0 0110.7 4h2.6a1.2 1.2 0 011.2 1.2V7M7 7l.8 12a2 2 0 002 1.8h4.4a2 2 0 002-1.8L17 7M10 11v6M14 11v6" ${st}/>`, 'fill="none" stroke="currentColor"'),
    check:  S(`<path d="M4.5 12.8l4.7 4.7L19.5 7" ${st}/>`, 'fill="none" stroke="currentColor"'),
    warn:   S(`<path d="M12 3.5l9.3 16.2H2.7z"/><path d="M12 9.6v4.4M12 16.9v.2" ${st}/>`, 'fill="none" stroke="currentColor"'),
    errorx: S(`<circle cx="12" cy="12" r="9"/><path d="M8.8 8.8l6.4 6.4M15.2 8.8l-6.4 6.4" ${st}/>`, 'fill="none" stroke="currentColor"'),
    info:   S(`<circle cx="12" cy="12" r="9"/><path d="M12 11v5.4M12 7.6v.2" ${st}/>`, 'fill="none" stroke="currentColor"'),
    wav:    S(`<path d="M4 12h2l2.4-5.4 3 10.8 2.6-7 1.8 1.6H20" ${st}/>`),
    mp3:    S(`<rect x="3.5" y="6.5" width="17" height="11" rx="2.4"/><path d="M7 10h1.8a1.5 1.5 0 010 3H7zm0 3v-3zM12.5 10h1.8a1.5 1.5 0 010 3h-1.8zm0 3v-3M17.5 10.6l1-.4v4" ${st}/>`, 'fill="none" stroke="currentColor"'),
  };

  window.renderIcons = function renderIcons(root = document) {
    root.querySelectorAll("i[data-ico]").forEach((el) => {
      const key = el.getAttribute("data-ico");
      if (!ICONS[key]) return;
      const holder = document.createElement("span");
      holder.innerHTML = ICONS[key];
      const svg = holder.firstChild;
      // Giữ nguyên class/hidden — logic UI (ico-play/ico-pause) dựa vào đây.
      if (el.getAttribute("class")) svg.setAttribute("class", el.getAttribute("class"));
      if (el.hasAttribute("hidden")) svg.setAttribute("hidden", "");
      el.replaceWith(svg);
    });
  };
  window.ICONS = ICONS;
})();
