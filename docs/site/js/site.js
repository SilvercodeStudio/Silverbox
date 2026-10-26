// The theme button and the full-size image viewer. The pages work without this script: they follow the
// system appearance, the theme button stays hidden, and an image link opens the image itself.
(function () {
  var root = document.documentElement;
  var systemLight = window.matchMedia("(prefers-color-scheme: light)");

  // ---------- Theme ----------
  // A choice is kept only while it differs from the system appearance, so the page follows the system
  // again once the two agree.
  function storedTheme() {
    try { return localStorage.getItem("theme"); } catch (e) { return null; }
  }
  function storeTheme(theme) {
    try {
      if (theme) localStorage.setItem("theme", theme); else localStorage.removeItem("theme");
    } catch (e) {}
  }
  function systemTheme() { return systemLight.matches ? "light" : "dark"; }

  var button = document.querySelector(".theme-btn");
  function applyTheme(theme) {
    root.dataset.theme = theme;
    // Each <picture> offers its light screenshot through a source for prefers-color-scheme: light.
    // Point that source at the chosen theme instead.
    document.querySelectorAll("source[data-theme-light]").forEach(function (source) {
      source.media = theme === "light" ? "all" : "not all";
    });
    if (button) {
      var label = theme === "light" ? "Switch to dark appearance" : "Switch to light appearance";
      button.setAttribute("aria-label", label);
      button.title = label;
    }
  }

  applyTheme(storedTheme() || systemTheme());
  systemLight.addEventListener("change", function () {
    if (!storedTheme()) applyTheme(systemTheme());
  });
  if (button) {
    button.hidden = false;
    button.addEventListener("click", function () {
      var next = root.dataset.theme === "light" ? "dark" : "light";
      storeTheme(next === systemTheme() ? null : next);
      applyTheme(next);
    });
  }

  // ---------- Image viewer ----------
  // An image link opens its full-size screenshot, in the current theme, over the page. A click anywhere
  // or Escape closes it.
  var links = document.querySelectorAll("a.zoom");
  if (!links.length || typeof HTMLDialogElement !== "function") return;
  var viewer = document.createElement("dialog");
  viewer.className = "viewer";
  viewer.setAttribute("aria-label", "Screenshot");
  var image = document.createElement("img");
  viewer.appendChild(image);
  document.body.appendChild(viewer);
  viewer.addEventListener("click", function () { viewer.close(); });
  viewer.addEventListener("close", function () { image.removeAttribute("src"); });

  links.forEach(function (link) {
    link.addEventListener("click", function (event) {
      // Command-click and the like still open the image in a new tab.
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return;
      event.preventDefault();
      var thumbnail = link.querySelector("img");
      image.src = root.dataset.theme === "light" && link.dataset.light ? link.dataset.light : link.href;
      image.alt = thumbnail ? thumbnail.alt : "";
      viewer.showModal();
    });
  });
})();
