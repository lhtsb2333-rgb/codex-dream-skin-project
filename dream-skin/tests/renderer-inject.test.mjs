import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const windowsRoot = path.resolve(here, "..");
const template = await fs.readFile(path.join(windowsRoot, "assets", "renderer-inject.js"), "utf8");
const css = await fs.readFile(path.join(windowsRoot, "assets", "dream-skin.css"), "utf8");
const buildPayload = (config = {}) => template
  .replace("__DREAM_CSS_JSON__", JSON.stringify(".fixture { color: blue; }"))
  .replace("__DREAM_ART_JSON__", JSON.stringify("data:image/png;base64,AA=="))
  .replace("__DREAM_THEME_JSON__", JSON.stringify(config));
const payload = buildPayload();

assert.doesNotMatch(
  css,
  /main\s*>\s*header\s*\{[^}]*\b(?:position|z-index)\s*:/,
  "The skin must preserve Codex's native fixed header so the side-panel toggle remains reachable.",
);
assert.match(
  css,
  /main\.dream-home-shell\s*\{[^}]*background-image:/s,
  "Empty-project art must be attached to the stable main shell.",
);
assert.doesNotMatch(
  css,
  /\.dream-home\s*>\s*div:first-child/,
  "Home styling must not depend on version-specific anonymous wrapper positions.",
);
assert.doesNotMatch(
  css,
  /\.dream-home \.group\\\/home-suggestions button\s*\{[^}]*(?:min-height|padding)\s*:/s,
  "Empty-project suggestion styling must not change native card geometry.",
);
assert.doesNotMatch(
  css,
  /\.dream-home \[data-feature="game-source"\]\s*\{[^}]*(?:display|flex-direction|font-size)\s*:/s,
  "Empty-project title styling must not change native layout geometry.",
);
assert.doesNotMatch(
  css,
  /html\.codex-dream-skin main\s*\{[^}]*(?:position|overflow|isolation|min-height)\s*:/s,
  "The shell must keep Codex's native layout and clipping behavior.",
);
assert.doesNotMatch(
  css,
  /dream-home-utility|\.dream-home:has\(\.dream-home-utility\)/,
  "The home utility bar must retain Codex's native geometry rather than being merged with the composer.",
);

function createFixture({
  shellPresent,
  legacyShellPresent = shellPresent,
  mainPresent = shellPresent,
  sidebarPresent = shellPresent,
  staleSkin = false,
  homePresent = false,
  utilityPresent = false,
  threadPresent = true,
  shellAppearance = "dark",
  computedColorScheme = "",
  osAppearance = "light",
  analysisFixture = null,
}) {
  const nodes = new Map();
  const rootClasses = new Set(staleSkin ? ["codex-dream-skin"] : []);
  const rootStyles = new Map(staleSkin ? [["--dream-art", "url(\"blob:stale\")"]] : []);
  const revokedUrls = [];
  const observers = [];
  let objectUrlCount = 0;
  let hasMain = mainPresent;
  let hasSidebar = sidebarPresent;
  let root;

  const queueRootClassMutation = () => {
    for (const observer of observers) {
      if (observer.target !== root || !observer.options?.attributes) continue;
      if (observer.options.attributeFilter && !observer.options.attributeFilter.includes("class")) continue;
      observer.records.push({ type: "attributes", attributeName: "class", target: root });
    }
  };
  const makeClassList = (classes = new Set(), onMutation = () => {}) => ({
    add(...values) {
      let changed = false;
      for (const value of values) {
        if (!classes.has(value)) { classes.add(value); changed = true; }
      }
      if (changed) onMutation();
    },
    remove(...values) {
      let changed = false;
      for (const value of values) changed = classes.delete(value) || changed;
      if (changed) onMutation();
    },
    toggle(value, enabled) {
      const changed = enabled ? !classes.has(value) : classes.has(value);
      if (enabled) classes.add(value);
      else classes.delete(value);
      if (changed) onMutation();
    },
    contains(value) { return classes.has(value); },
  });

  root = {
    className: shellAppearance,
    classList: makeClassList(rootClasses, queueRootClassMutation),
    getAttribute() { return null; },
    style: {
      setProperty(key, value) { rootStyles.set(key, value); },
      removeProperty(key) { rootStyles.delete(key); },
    },
    appendChild(node) {
      node.parentElement = root;
      nodes.set(node.id, node);
    },
  };
  const body = {
    className: "",
    getAttribute() { return null; },
    appendChild(node) {
      node.parentElement = body;
      nodes.set(node.id, node);
    },
  };
  const shellClasses = new Set();
  const shellMain = {
    classList: makeClassList(shellClasses),
    getBoundingClientRect() {
      return { left: 290, top: 36, width: 990, height: 784 };
    },
  };
  const routeClasses = new Set();
  const utilityClasses = new Set();
  const utilityNode = { classList: makeClassList(utilityClasses) };
  const routeMain = {
    classList: makeClassList(routeClasses),
    matches(selector) {
      if (selector === '[class*="container-name:home-main-content"]') return homePresent;
      return false;
    },
    querySelector(selector) {
      if (selector === '.thread-scroll-container, [data-thread-scroll-footer], [data-message-author-role]') {
        return threadPresent ? {} : null;
      }
      if (selector === '[data-testid="home-icon"], [class~="group/home-suggestions"], [class*="_homeUtilityBar_"]') {
        return homePresent ? {} : null;
      }
      return null;
    },
    querySelectorAll(selector) {
      if (selector === '[class*="_homeUtilityBar_"]' && utilityPresent) return [utilityNode];
      return [];
    },
  };
  const staleHome = { classList: makeClassList(new Set(["dream-home"])) };
  const staleShell = { classList: makeClassList(new Set(["dream-home-shell"])) };

  const createElement = (tagName) => {
    if (tagName === "canvas" && analysisFixture) {
      return {
        width: 0,
        height: 0,
        getContext() {
          return {
            drawImage() {},
            getImageData() { return { data: analysisFixture.pixels }; },
          };
        },
      };
    }
    return {
      id: "",
      dataset: {},
      style: {},
      classList: makeClassList(),
      parentElement: null,
      textContent: "",
      innerHTML: "",
      setAttribute() {},
      remove() { nodes.delete(this.id); },
    };
  };
  if (staleSkin) {
    const style = createElement();
    style.id = "codex-dream-skin-style";
    nodes.set(style.id, style);
    const chrome = createElement();
    chrome.id = "codex-dream-skin-chrome";
    nodes.set(chrome.id, chrome);
  }

  const document = {
    documentElement: root,
    head: root,
    body,
    createElement,
    getElementById(id) { return nodes.get(id) ?? null; },
    querySelector(selector) {
      if (selector === "main.main-surface") return hasMain && legacyShellPresent ? shellMain : null;
      if (selector === "main") return hasMain ? shellMain : null;
      if (selector === "aside.app-shell-left-panel") return hasSidebar ? {} : null;
      if (selector === '[role="main"]') return hasMain ? routeMain : null;
      return null;
    },
    querySelectorAll(selector) {
      if (selector === '[role="main"]') return hasMain ? [routeMain] : [];
      if (selector === ".dream-task") return routeClasses.has("dream-task") ? [routeMain] : [];
      if (selector === ".dream-thread") return routeClasses.has("dream-thread") ? [routeMain] : [];
      if (selector === ".dream-home-utility") {
        return utilityClasses.has("dream-home-utility") ? [utilityNode] : [];
      }
      if (!staleSkin) return [];
      if (selector === ".dream-home") return [staleHome];
      if (selector === ".dream-home-shell") return [staleShell];
      if (selector === ".dream-thread-shell") return [];
      return [];
    },
  };
  const context = {
    window: {
      matchMedia() { return { matches: osAppearance === "dark" }; },
    },
    document,
    MutationObserver: class {
      constructor(callback) {
        this.callback = callback;
        this.records = [];
        this.target = null;
        this.options = null;
        observers.push(this);
      }
      observe(target, options = {}) {
        this.target = target;
        this.options = options;
      }
      disconnect() {
        this.target = null;
        this.records = [];
      }
      takeRecords() {
        const records = this.records;
        this.records = [];
        return records;
      }
    },
    URL: {
      createObjectURL() { objectUrlCount += 1; return `blob:fixture-${objectUrlCount}`; },
      revokeObjectURL(value) { revokedUrls.push(value); },
    },
    Blob,
    Uint8Array,
    atob,
    setInterval: () => 1,
    clearInterval: () => {},
    setTimeout: () => 2,
    clearTimeout: () => {},
    getComputedStyle() { return { colorScheme: computedColorScheme }; },
  };
  if (analysisFixture) {
    context.Image = class {
      naturalWidth = analysisFixture.naturalWidth;
      naturalHeight = analysisFixture.naturalHeight;
      set src(_) { this.onload(); }
    };
  }

  return {
    context,
    nodes,
    observers,
    rootClasses,
    rootStyles,
    revokedUrls,
    routeClasses,
    shellClasses,
    utilityClasses,
    setShellPresent(value) {
      hasMain = value;
      hasSidebar = value;
    },
    setSidebarPresent(value) { hasSidebar = value; },
    setMainPresent(value) { hasMain = value; },
    setHomePresent(value) { homePresent = value; },
    setThreadPresent(value) { threadPresent = value; },
  };
}

const main = createFixture({ shellPresent: true });
const mainResult = vm.runInNewContext(payload, main.context);
assert.equal(mainResult.installed, true);
assert.equal(main.rootClasses.has("codex-dream-skin"), true);
assert.equal(main.rootStyles.get("--dream-art"), 'url("blob:fixture-1")');
assert.equal(main.nodes.has("codex-dream-skin-style"), true);
assert.equal(main.nodes.has("codex-dream-skin-chrome"), true);
assert.equal(main.rootClasses.has("dream-theme-dark"), true);
assert.equal(main.rootClasses.has("dream-art-standard"), true);
assert.equal(main.rootClasses.has("dream-task-ambient"), true);
assert.equal(main.routeClasses.has("dream-task"), true);
assert.equal(main.routeClasses.has("dream-thread"), true);
assert.equal(main.shellClasses.has("dream-thread-shell"), true);
assert.equal(main.context.window.__CODEX_DREAM_SKIN_STATE__.cleanup(), true);
assert.equal(main.rootClasses.has("codex-dream-skin"), false);
assert.equal(main.rootClasses.has("dream-theme-dark"), false);
assert.equal(main.nodes.has("codex-dream-skin-style"), false);
assert.equal(main.nodes.has("codex-dream-skin-chrome"), false);
assert.deepEqual(main.revokedUrls, ["blob:fixture-1"]);

// ChatGPT 26.727 removed the legacy main.main-surface class while retaining
// the semantic main element. The skin must not depend on the old class.
const modernShell = createFixture({ shellPresent: true, legacyShellPresent: false });
const modernResult = vm.runInNewContext(payload, modernShell.context);
assert.equal(modernResult.installed, true);
assert.equal(modernShell.rootClasses.has("codex-dream-skin"), true);
assert.equal(modernShell.routeClasses.has("dream-thread"), true);
assert.equal(modernShell.shellClasses.has("dream-thread-shell"), true);

const emptyProject = createFixture({
  shellPresent: true,
  homePresent: true,
  utilityPresent: true,
  threadPresent: false,
});
vm.runInNewContext(payload, emptyProject.context);
assert.equal(emptyProject.routeClasses.has("dream-home"), true);
assert.equal(emptyProject.routeClasses.has("dream-task"), false);
assert.equal(emptyProject.routeClasses.has("dream-thread"), false);
assert.equal(emptyProject.shellClasses.has("dream-home-shell"), true);
assert.equal(emptyProject.shellClasses.has("dream-thread-shell"), false);
assert.equal(emptyProject.utilityClasses.has("dream-home-utility"), false,
  "The native home utility bar must not receive a geometry-changing theme marker.");
assert.equal(emptyProject.rootClasses.has("codex-dream-skin"), true);

// React keeps the outer shell when a thread becomes a new-chat page. Route
// classes left on that shell must be removed before the home state is styled.
emptyProject.shellClasses.add("dream-task", "dream-thread");
emptyProject.context.window.__CODEX_DREAM_SKIN_STATE__.ensure();
assert.equal(emptyProject.shellClasses.has("dream-task"), false);
assert.equal(emptyProject.shellClasses.has("dream-thread"), false);
assert.equal(emptyProject.shellClasses.has("dream-home-shell"), true);

// Sending the first message replaces the welcome route with a conversation.
// The observer's ensure pass must switch states without losing the theme.
emptyProject.setHomePresent(false);
emptyProject.setThreadPresent(true);
emptyProject.context.window.__CODEX_DREAM_SKIN_STATE__.ensure();
assert.equal(emptyProject.routeClasses.has("dream-home"), false);
assert.equal(emptyProject.routeClasses.has("dream-task"), true);
assert.equal(emptyProject.routeClasses.has("dream-thread"), true);
assert.equal(emptyProject.shellClasses.has("dream-home-shell"), false);
assert.equal(emptyProject.shellClasses.has("dream-thread-shell"), true);
assert.equal(emptyProject.utilityClasses.has("dream-home-utility"), false);
assert.equal(emptyProject.rootClasses.has("codex-dream-skin"), true);

const genericRoute = createFixture({ shellPresent: true, threadPresent: false });
vm.runInNewContext(payload, genericRoute.context);
assert.equal(genericRoute.routeClasses.has("dream-task"), true);
assert.equal(genericRoute.routeClasses.has("dream-home"), false);
assert.equal(genericRoute.routeClasses.has("dream-thread"), false);
assert.equal(genericRoute.shellClasses.has("dream-home-shell"), false);
assert.equal(genericRoute.shellClasses.has("dream-thread-shell"), false);
assert.equal(genericRoute.rootClasses.has("codex-dream-skin"), true);

const reinjected = createFixture({ shellPresent: true });
vm.runInNewContext(payload, reinjected.context);
const firstState = reinjected.context.window.__CODEX_DREAM_SKIN_STATE__;
vm.runInNewContext(payload, reinjected.context);
const secondState = reinjected.context.window.__CODEX_DREAM_SKIN_STATE__;
assert.notEqual(secondState.installToken, firstState.installToken);
assert.equal(secondState.artUrl, "blob:fixture-2");
assert.equal(reinjected.rootStyles.get("--dream-art"), 'url("blob:fixture-2")');
assert.deepEqual(reinjected.revokedUrls, ["blob:fixture-1"]);
assert.equal(firstState.cleanup(), false);
assert.equal(secondState.cleanup(), true);

const auxiliary = createFixture({ shellPresent: false, staleSkin: true });
const auxiliaryResult = vm.runInNewContext(payload, auxiliary.context);
assert.equal(auxiliaryResult.installed, true);
assert.equal(auxiliary.rootClasses.has("codex-dream-skin"), false);
assert.equal(auxiliary.rootStyles.has("--dream-art"), false);
assert.equal(auxiliary.nodes.has("codex-dream-skin-style"), false);
assert.equal(auxiliary.nodes.has("codex-dream-skin-chrome"), false);

auxiliary.setShellPresent(true);
auxiliary.context.window.__CODEX_DREAM_SKIN_STATE__.ensure();
assert.equal(auxiliary.rootClasses.has("codex-dream-skin"), true);
assert.equal(auxiliary.nodes.has("codex-dream-skin-style"), true);
assert.equal(auxiliary.nodes.has("codex-dream-skin-chrome"), true);

// Collapsing the left rail removes aside.app-shell-left-panel while the main
// surface remains. The active theme must stay applied instead of flashing the
// native Codex chrome.
const collapsedSidebar = createFixture({
  shellPresent: true,
  mainPresent: true,
  sidebarPresent: false,
  staleSkin: true,
});
const collapsedResult = vm.runInNewContext(payload, collapsedSidebar.context);
assert.equal(collapsedResult.installed, true);
assert.equal(collapsedSidebar.rootClasses.has("codex-dream-skin"), true);
assert.equal(collapsedSidebar.rootStyles.has("--dream-art"), true);
assert.equal(collapsedSidebar.nodes.has("codex-dream-skin-style"), true);
assert.equal(collapsedSidebar.nodes.has("codex-dream-skin-chrome"), true);
assert.equal(collapsedSidebar.rootClasses.has("dream-theme-dark"), true);

collapsedSidebar.setSidebarPresent(false);
collapsedSidebar.context.window.__CODEX_DREAM_SKIN_STATE__.ensure();
assert.equal(collapsedSidebar.rootClasses.has("codex-dream-skin"), true);
assert.equal(collapsedSidebar.nodes.has("codex-dream-skin-style"), true);

collapsedSidebar.setMainPresent(false);
collapsedSidebar.context.window.__CODEX_DREAM_SKIN_STATE__.ensure();
assert.equal(collapsedSidebar.rootClasses.has("codex-dream-skin"), false);
assert.equal(collapsedSidebar.nodes.has("codex-dream-skin-style"), false);

const configured = createFixture({
  shellPresent: true,
  homePresent: true,
  utilityPresent: true,
  threadPresent: false,
});
const configuredPayload = buildPayload({
  appearance: "light",
  palette: { accent: "#d45a70" },
  art: { focusX: .15, focusY: .8, safeArea: "right", taskMode: "off" },
});
const configuredResult = vm.runInNewContext(configuredPayload, configured.context);
assert.equal(configuredResult.adaptive, true);
assert.equal(configured.rootClasses.has("dream-theme-light"), true);
assert.equal(configured.rootClasses.has("dream-theme-dark"), false);
assert.equal(configured.rootClasses.has("dream-focus-left"), true);
assert.equal(configured.rootClasses.has("dream-safe-right"), true);
assert.equal(configured.rootClasses.has("dream-task-off"), true);
assert.equal(configured.rootStyles.get("--dream-art-position"), "15% 80%");
assert.equal(configured.rootStyles.get("--dream-accent"), "#d45a70");
assert.equal(configured.routeClasses.has("dream-home"), true);
assert.equal(configured.routeClasses.has("dream-task"), false);
assert.equal(configured.utilityClasses.has("dream-home-utility"), false);
assert.equal(configured.context.window.__CODEX_DREAM_SKIN_STATE__.cleanup(), true);
assert.equal(configured.utilityClasses.has("dream-home-utility"), false);

const analysisPixels = new Uint8ClampedArray(48 * 12 * 4);
for (let index = 0; index < 48 * 12; index += 1) {
  const offset = index * 4;
  const x = index % 48;
  const subject = x >= 34 && x <= 42;
  analysisPixels[offset] = subject ? 210 : 246;
  analysisPixels[offset + 1] = subject ? 84 : 239;
  analysisPixels[offset + 2] = subject ? 112 : 237;
  analysisPixels[offset + 3] = 255;
}
const analyzed = createFixture({
  shellPresent: true,
  analysisFixture: { naturalWidth: 1200, naturalHeight: 400, pixels: analysisPixels },
});
vm.runInNewContext(payload, analyzed.context);
await Promise.resolve();
assert.equal(analyzed.rootClasses.has("dream-theme-dark"), true);
assert.equal(analyzed.rootClasses.has("dream-theme-light"), false);
assert.equal(analyzed.rootClasses.has("dream-art-wide"), true);
assert.equal(analyzed.rootClasses.has("dream-task-banner"), true);
assert.equal(analyzed.rootClasses.has("dream-safe-left"), true);
assert.notEqual(analyzed.rootStyles.get("--dream-accent"), "rgb(216 104 119)");

const standardArt = createFixture({
  shellPresent: true,
  analysisFixture: { naturalWidth: 800, naturalHeight: 800, pixels: analysisPixels },
});
vm.runInNewContext(payload, standardArt.context);
await Promise.resolve();
assert.equal(standardArt.rootClasses.has("dream-art-standard"), true);
assert.equal(standardArt.rootClasses.has("dream-task-ambient"), true);
assert.equal(standardArt.rootClasses.has("dream-task-banner"), false);

const mediumWide = createFixture({
  shellPresent: true,
  analysisFixture: { naturalWidth: 2100, naturalHeight: 1000, pixels: analysisPixels },
});
vm.runInNewContext(payload, mediumWide.context);
await Promise.resolve();
assert.equal(mediumWide.rootClasses.has("dream-art-wide"), true);
assert.equal(mediumWide.rootClasses.has("dream-task-ambient"), true);
assert.equal(mediumWide.rootClasses.has("dream-task-banner"), false);

const nativeLight = createFixture({ shellPresent: true, shellAppearance: "light" });
vm.runInNewContext(payload, nativeLight.context);
assert.equal(nativeLight.rootClasses.has("dream-theme-light"), true);
assert.equal(nativeLight.rootClasses.has("dream-theme-dark"), false);

const nativeComputedDark = createFixture({
  shellPresent: true,
  shellAppearance: "",
  computedColorScheme: "dark",
  osAppearance: "light",
});
vm.runInNewContext(payload, nativeComputedDark.context);
assert.equal(nativeComputedDark.rootClasses.has("dream-theme-dark"), true);
assert.equal(nativeComputedDark.rootClasses.has("dream-theme-light"), false);
nativeComputedDark.context.window.__CODEX_DREAM_SKIN_STATE__.ensure();
assert.equal(nativeComputedDark.rootClasses.has("dream-theme-dark"), true);
const nativeObserver = nativeComputedDark.observers[0];
nativeObserver.takeRecords();
nativeComputedDark.context.window.__CODEX_DREAM_SKIN_STATE__.ensure();
assert.equal(nativeObserver.takeRecords().length, 0,
  "Sampling the native computed color-scheme must not queue a self-triggering root mutation pass.");

const metadataWide = createFixture({ shellPresent: true });
vm.runInNewContext(buildPayload({ artMetadata: { ratio: 16 / 9 } }), metadataWide.context);
assert.equal(metadataWide.rootClasses.has("dream-art-wide"), true);
assert.equal(metadataWide.rootClasses.has("dream-art-standard"), false);

console.log("PASS: renderer applies adaptive theme metadata, keeps skin without a sidebar, and preserves transparent auxiliary windows.");
