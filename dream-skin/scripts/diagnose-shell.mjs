const args = process.argv.slice(2);
const readOption = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
};
const port = Number.parseInt(readOption("--port", "9335"), 10);
if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error("--port must be an integer between 1024 and 65535");
}

const endpoint = `http://127.0.0.1:${port}`;
const response = await fetch(`${endpoint}/json/list`);
if (!response.ok) throw new Error(`CDP endpoint returned HTTP ${response.status}`);
const targets = await response.json();
const appTargets = targets.filter((target) => target.type === "page" &&
  String(target.url || "").startsWith("app://-"));

async function inspectTarget(target) {
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let nextId = 0;
  const pending = new Map();
  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    const handler = pending.get(message.id);
    if (!handler) return;
    pending.delete(message.id);
    handler(message);
  });
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", () => reject(new Error("WebSocket open failed")), { once: true });
  });
  const send = (method, params = {}) => new Promise((resolve) => {
    const id = ++nextId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
  const expression = `(() => {
    const shell = document.querySelector("main.main-surface") || document.querySelector("main");
    const routeMain = document.querySelector('[role="main"]');
    const composer = document.querySelector('.composer-surface-chrome') ||
      document.querySelector('textarea:not([aria-hidden="true"]), [role="textbox"][contenteditable="true"], [contenteditable="true"]');
    const hasThread = Boolean(routeMain?.matches?.(".thread-scroll-container") ||
      routeMain?.querySelector?.(".thread-scroll-container, [data-thread-scroll-footer], [data-message-author-role]"));
    const hasHome = !hasThread && Boolean(
      routeMain?.matches?.('[class*="container-name:home-main-content"]') ||
      routeMain?.querySelector?.('[data-testid="home-icon"], [class~="group/home-suggestions"], [class*="_homeUtilityBar_"]')
    );
    const classList = (node) => node ? [...node.classList].slice(0, 40) : [];
    return {
      protocol: location.protocol,
      legacyShellClass: Boolean(document.querySelector("main.main-surface")),
      semanticMainElement: Boolean(document.querySelector("main")),
      sidebar: Boolean(document.querySelector("aside.app-shell-left-panel")),
      composer: Boolean(composer),
      routeMain: Boolean(routeMain),
      homeMarkers: hasHome,
      threadMarkers: hasThread,
      classification: hasThread ? "thread" : hasHome ? "home-or-empty-project" : "generic",
      compatibleIdentity: location.protocol === "app:" && Boolean(shell) &&
        Boolean(document.querySelector("aside.app-shell-left-panel")) &&
        Boolean(composer || routeMain),
      injected: document.documentElement.classList.contains("codex-dream-skin"),
      skinVersion: window.__CODEX_DREAM_SKIN_STATE__?.version ?? null,
      stylePresent: Boolean(document.getElementById("codex-dream-skin-style")),
      shellClasses: classList(shell),
      routeClasses: classList(routeMain),
    };
  })()`;
  const message = await send("Runtime.evaluate", { expression, returnByValue: true });
  ws.close();
  if (message.error) throw new Error(message.error.message);
  if (message.result?.exceptionDetails) throw new Error(message.result.exceptionDetails.text);
  return {
    id: target.id,
    url: target.url,
    title: target.title,
    ...message.result.result.value,
  };
}

const inspected = [];
for (const target of appTargets) {
  try {
    inspected.push(await inspectTarget(target));
  } catch (error) {
    inspected.push({ id: target.id, url: target.url, title: target.title, error: error.message });
  }
}

const report = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  endpoint,
  targetCount: inspected.length,
  compatibleTargetCount: inspected.filter((item) => item.compatibleIdentity).length,
  targets: inspected,
};
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
