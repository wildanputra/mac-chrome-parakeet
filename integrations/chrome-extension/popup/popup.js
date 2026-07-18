// MacParakeet Meeting Recorder — popup controller.
//
// Pure view over the service worker's status: one getStatus round trip on
// open, then optimistic re-queries after each action. All bridge/native
// logic lives in background.js.

"use strict";

const el = {
  pill: document.getElementById("status-pill"),
  statusLine: document.getElementById("status-line"),
  meetingLine: document.getElementById("meeting-line"),
  recordBtn: document.getElementById("record-btn"),
  stopBtn: document.getElementById("stop-btn"),
  launchBtn: document.getElementById("launch-btn"),
  helpLink: document.getElementById("help-link"),
  fixCommand: document.getElementById("fix-command"),
  promptOnJoin: document.getElementById("prompt-on-join"),
  autoStop: document.getElementById("auto-stop"),
};

const PLATFORM_LABELS = {
  google_meet: "Google Meet",
  zoom: "Zoom",
  teams: "Microsoft Teams",
  webex: "Webex",
};

let currentMeeting = null; // {tabId, platform, title}

function send(message) {
  return chrome.runtime.sendMessage(message);
}

function setPill(kind, text) {
  el.pill.className = `pill pill-${kind}`;
  el.pill.textContent = text;
}

function showActions({ record = false, stop = false, launch = false, help = false }) {
  el.recordBtn.hidden = !record;
  el.stopBtn.hidden = !stop;
  el.launchBtn.hidden = !launch;
  el.helpLink.hidden = !help;
}

function showFix(command) {
  el.fixCommand.hidden = !command;
  el.fixCommand.textContent = command || "";
}

function pickActiveMeeting(meetings) {
  const entries = Object.entries(meetings || {})
    .map(([tabId, m]) => ({ tabId: Number(tabId), ...m }))
    .filter((m) => m.inCall)
    .sort((a, b) => b.updatedAt - a.updatedAt);
  return entries[0] || null;
}

function render(status) {
  el.promptOnJoin.checked = !!status.settings.promptOnJoin;
  el.autoStop.checked = !!status.settings.autoStopOnLeave;

  currentMeeting = pickActiveMeeting(status.meetings);
  if (currentMeeting) {
    const label = PLATFORM_LABELS[currentMeeting.platform] || currentMeeting.platform;
    el.meetingLine.hidden = false;
    el.meetingLine.textContent = currentMeeting.title
      ? `${label}: ${currentMeeting.title}`
      : `${label} call detected`;
  } else {
    el.meetingLine.hidden = true;
  }

  showFix(null);

  if (status.error) {
    renderError(status.error);
    return;
  }

  const state = status.state;
  if (!state.bridgeEnabled) {
    setPill("error", "Disabled");
    el.statusLine.textContent =
      "The app is running, but the Chrome bridge is switched off. Enable it in Terminal:";
    showFix("macparakeet-cli config set chrome-extension on");
    showActions({ help: true });
    return;
  }

  if (state.recording) {
    setPill("recording", "Recording");
    el.statusLine.textContent = "MacParakeet is recording this meeting on your Mac.";
    showActions({ stop: true });
    return;
  }

  setPill("ok", "Ready");
  el.statusLine.textContent = currentMeeting
    ? "Ready to record — audio stays on your Mac."
    : "No call detected in this browser. You can still start a recording manually.";
  showActions({ record: true });
  el.recordBtn.textContent = currentMeeting ? "Start recording this meeting" : "Start recording";
}

function renderError(error) {
  switch (error.code) {
    case "host_not_installed":
      setPill("error", "Not set up");
      el.statusLine.textContent =
        "The native bridge isn’t installed yet. Run the installer from the MacParakeet repo, then reopen this popup:";
      showFix("integrations/chrome-extension/native-host/install.sh");
      showActions({ help: true });
      break;
    case "app_unreachable":
      setPill("error", "App not running");
      el.statusLine.textContent = "MacParakeet isn’t running (or hasn’t finished launching).";
      showActions({ launch: true, help: true });
      break;
    case "bridge_disabled":
      setPill("error", "Disabled");
      el.statusLine.textContent =
        "The Chrome bridge is switched off. Enable it in Terminal:";
      showFix("macparakeet-cli config set chrome-extension on");
      showActions({ help: true });
      break;
    default:
      setPill("error", "Error");
      el.statusLine.textContent = error.message || "Something went wrong talking to the bridge.";
      showActions({ launch: true, help: true });
  }
}

async function refresh() {
  let status;
  try {
    status = await send({ kind: "getStatus" });
  } catch (error) {
    // sendMessage rejects when the service worker can't be reached (e.g. the
    // extension was just updated) — without this the popup would sit on
    // "Checking the bridge…" forever.
    renderError({ code: "unknown", message: "Could not reach the extension. Close and reopen this popup." });
    return;
  }
  if (status && status.ok) render(status);
  else if (status && status.error) renderError(status.error);
}

async function act(button, message) {
  button.disabled = true;
  try {
    const result = await send(message);
    if (result && !result.ok && result.error) {
      renderError(result.error);
      return;
    }
    await refresh();
  } catch (error) {
    renderError({ code: "unknown", message: String((error && error.message) || error) });
  } finally {
    button.disabled = false;
  }
}

el.recordBtn.addEventListener("click", () => {
  act(el.recordBtn, {
    kind: "startRecording",
    title: currentMeeting ? currentMeeting.title : null,
    platform: currentMeeting ? currentMeeting.platform : null,
    tabId: currentMeeting ? currentMeeting.tabId : null,
  });
});

el.stopBtn.addEventListener("click", () => act(el.stopBtn, { kind: "stopRecording" }));
el.launchBtn.addEventListener("click", () => act(el.launchBtn, { kind: "launchApp" }));

for (const [checkbox, key] of [
  [el.promptOnJoin, "promptOnJoin"],
  [el.autoStop, "autoStopOnLeave"],
]) {
  checkbox.addEventListener("change", () => {
    send({ kind: "setSettings", settings: { [key]: checkbox.checked } });
  });
}

refresh();
