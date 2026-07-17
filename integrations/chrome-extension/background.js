// MacParakeet Meeting Recorder — service worker (ADR-029).
//
// Owns the native messaging port to `macparakeet-cli chrome-native-host`,
// tracks which tabs are in a call (as reported by content/meeting-detector.js),
// prompts to record on call join, and keeps the toolbar badge honest.
//
// MV3 service workers are ephemeral: everything that must survive a worker
// restart lives in chrome.storage.session (cleared on browser restart, which
// is the semantics we want), and user settings live in chrome.storage.sync.

"use strict";

const HOST_NAME = "com.macparakeet.chrome_bridge";
const PROTOCOL_VERSION = 1;
// Must outlast the host's slowest path: launch_app waits ~2.5s before its
// state probe, which then has its own 2s app timeout.
const REQUEST_TIMEOUT_MS = 6000;
const MEETING_REPORT_STALE_MS = 20000; // detector heartbeats every 5s
const STATE_POLL_ALARM = "macparakeet-state-poll";

const PLATFORM_LABELS = {
  google_meet: "Google Meet",
  zoom: "Zoom",
  teams: "Microsoft Teams",
  webex: "Webex",
};

const DEFAULT_SETTINGS = {
  promptOnJoin: true, // Chrome notification with a "Start recording" button on call join
  autoStopOnLeave: true, // stop only recordings this extension started, when the call ends
};

// ---------------------------------------------------------------------------
// Native messaging port
// ---------------------------------------------------------------------------

let port = null;
let portBroken = null; // classification string when the last connect failed
const pending = new Map(); // request id -> {resolve, reject, timer}
let requestCounter = 0;

function connectPort() {
  if (port) return port;
  port = chrome.runtime.connectNative(HOST_NAME);
  portBroken = null;
  port.onMessage.addListener(onNativeMessage);
  port.onDisconnect.addListener(() => {
    const message = chrome.runtime.lastError ? chrome.runtime.lastError.message : "";
    portBroken = classifyDisconnect(message);
    port = null;
    for (const [, entry] of pending) {
      clearTimeout(entry.timer);
      entry.reject(new BridgeError(portBroken, message || "Native host disconnected"));
    }
    pending.clear();
  });
  return port;
}

function classifyDisconnect(message) {
  const text = (message || "").toLowerCase();
  if (text.includes("not found") || text.includes("forbidden")) return "host_not_installed";
  return "host_disconnected";
}

class BridgeError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function onNativeMessage(reply) {
  if (!reply || typeof reply !== "object") return;
  if (reply.replyTo && pending.has(reply.replyTo)) {
    const entry = pending.get(reply.replyTo);
    pending.delete(reply.replyTo);
    clearTimeout(entry.timer);
    entry.resolve(reply);
    return;
  }
  // Broadcast state (no correlation id) — refresh the badge opportunistically.
  if (reply.type === "state") {
    rememberState(reply).then(updateBadge);
  }
}

function sendNative(request) {
  return new Promise((resolve, reject) => {
    let activePort;
    try {
      activePort = connectPort();
    } catch (error) {
      reject(new BridgeError("host_not_installed", String(error)));
      return;
    }
    const id = `req-${Date.now()}-${++requestCounter}`;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new BridgeError("host_timeout", "Native host did not reply"));
    }, REQUEST_TIMEOUT_MS);
    pending.set(id, { resolve, reject, timer });
    try {
      activePort.postMessage({ v: PROTOCOL_VERSION, id, ...request });
    } catch (error) {
      pending.delete(id);
      clearTimeout(timer);
      reject(new BridgeError(portBroken || "host_disconnected", String(error)));
    }
  });
}

// ---------------------------------------------------------------------------
// Session state (survives service worker restarts)
// ---------------------------------------------------------------------------

async function getSession(defaults) {
  const stored = await chrome.storage.session.get(defaults);
  return stored;
}

async function getMeetings() {
  const { meetings = {} } = await getSession({ meetings: {} });
  return meetings;
}

async function setMeetings(meetings) {
  await chrome.storage.session.set({ meetings });
}

async function rememberState(reply) {
  const lastState = {
    recording: !!reply.recording,
    bridgeEnabled: reply.bridgeEnabled !== false,
    flowState: reply.flowState || "idle",
    at: Date.now(),
  };
  await chrome.storage.session.set({ lastState });
  return lastState;
}

async function getSettings() {
  return chrome.storage.sync.get(DEFAULT_SETTINGS);
}

// Which recording did we start, if any: {tabId, title} or null.
async function getStartedRecording() {
  const { startedRecording = null } = await getSession({ startedRecording: null });
  return startedRecording;
}

async function setStartedRecording(value) {
  await chrome.storage.session.set({ startedRecording: value });
}

// ---------------------------------------------------------------------------
// Bridge operations
// ---------------------------------------------------------------------------

async function fetchState() {
  const reply = await sendNative({ type: "get_state" });
  if (reply.type === "error") throw new BridgeError(reply.code, reply.message);
  return rememberState(reply);
}

async function startRecording(title, platform, tabId) {
  const reply = await sendNative({
    type: "start_recording",
    title: title || null,
    platform: platform || null,
  });
  if (reply.type === "error") throw new BridgeError(reply.code, reply.message);
  const state = await rememberState(reply);
  if (state.recording) {
    await setStartedRecording({ tabId: tabId ?? null, title: title || null });
  }
  await updateBadge();
  return state;
}

async function stopRecording() {
  const reply = await sendNative({ type: "stop_recording" });
  if (reply.type === "error") throw new BridgeError(reply.code, reply.message);
  await setStartedRecording(null);
  const state = await rememberState(reply);
  await updateBadge();
  return state;
}

async function launchApp() {
  const reply = await sendNative({ type: "launch_app" });
  if (reply.type === "error") throw new BridgeError(reply.code, reply.message);
  const state = await rememberState(reply);
  await updateBadge();
  return state;
}

// Forward active-speaker spans (ADR-029 speaker attribution) to the app,
// but only while a recording is actually running — otherwise participant
// names would leave the page for no benefit. The app applies them to the
// finished transcript by overlap voting; dropped batches only mean some
// speakers keep anonymous labels.
async function forwardSpeakerActivity(events) {
  const valid = (Array.isArray(events) ? events : [])
    .filter(
      (event) =>
        event &&
        typeof event.name === "string" &&
        event.name.trim() !== "" &&
        Number.isFinite(event.startMs) &&
        Number.isFinite(event.endMs) &&
        event.endMs > event.startMs
    )
    .slice(0, 200)
    .map((event) => ({
      name: event.name.trim().slice(0, 100),
      startMs: Math.round(event.startMs),
      endMs: Math.round(event.endMs),
    }));
  if (valid.length === 0) return;

  // The cached state can be stale (it only refreshes on polls/actions);
  // re-probe when old so recordings started from the app still get names.
  let { lastState = null } = await getSession({ lastState: null });
  if (!lastState || Date.now() - lastState.at > 30000) {
    try {
      lastState = await fetchState();
      await updateBadge();
    } catch {
      return; // host/app unreachable — drop the batch
    }
  }
  if (!lastState.recording) return;

  try {
    await sendNative({ type: "speaker_activity", events: valid });
  } catch {
    // App went away mid-recording; later batches will re-probe.
  }
}

// ---------------------------------------------------------------------------
// Badge
// ---------------------------------------------------------------------------

async function updateBadge() {
  const { lastState = null } = await getSession({ lastState: null });
  const meetings = await pruneStaleMeetings();
  const inCall = Object.values(meetings).some((m) => m.inCall);
  if (lastState && lastState.recording) {
    await chrome.action.setBadgeBackgroundColor({ color: "#D93025" });
    await chrome.action.setBadgeText({ text: "REC" });
  } else if (inCall) {
    await chrome.action.setBadgeBackgroundColor({ color: "#5F6368" });
    await chrome.action.setBadgeText({ text: "•" });
  } else {
    await chrome.action.setBadgeText({ text: "" });
  }
}

async function pruneStaleMeetings() {
  const meetings = await getMeetings();
  const now = Date.now();
  let changed = false;
  for (const [tabId, meeting] of Object.entries(meetings)) {
    if (now - meeting.updatedAt > MEETING_REPORT_STALE_MS) {
      delete meetings[tabId];
      changed = true;
    }
  }
  if (changed) await setMeetings(meetings);
  return meetings;
}

// ---------------------------------------------------------------------------
// Meeting lifecycle (reports from content scripts)
// ---------------------------------------------------------------------------

async function handleMeetingReport(tabId, report) {
  const meetings = await getMeetings();
  const previous = meetings[tabId];
  const wasInCall = !!(previous && previous.inCall);
  meetings[tabId] = {
    platform: report.platform,
    title: report.title || "",
    inCall: !!report.inCall,
    updatedAt: Date.now(),
  };
  await setMeetings(meetings);

  if (!wasInCall && report.inCall) {
    await onCallJoined(tabId, meetings[tabId]);
  } else if (wasInCall && !report.inCall) {
    await onCallLeft(tabId);
  }
  await updateBadge();
}

async function onCallJoined(tabId, meeting) {
  const settings = await getSettings();
  if (!settings.promptOnJoin) return;

  // Don't prompt when already recording (whatever started it).
  let recording = false;
  try {
    recording = (await fetchState()).recording;
  } catch {
    // App/host unreachable — the prompt is still useful; clicking it will
    // surface the actionable error via notification.
  }
  if (recording) return;

  const label = PLATFORM_LABELS[meeting.platform] || "your meeting";
  chrome.notifications.create(`macparakeet-join-${tabId}`, {
    type: "basic",
    iconUrl: "icons/icon128.png",
    title: "Record this meeting?",
    message: meeting.title
      ? `MacParakeet can record “${meeting.title}” (${label}).`
      : `MacParakeet can record this ${label} call.`,
    buttons: [{ title: "Start recording" }],
    priority: 1,
  });
}

async function onCallLeft(tabId) {
  chrome.notifications.clear(`macparakeet-join-${tabId}`);
  const settings = await getSettings();
  const started = await getStartedRecording();
  if (!settings.autoStopOnLeave || !started || started.tabId !== tabId) return;
  try {
    await stopRecording();
    chrome.notifications.create("macparakeet-stopped", {
      type: "basic",
      iconUrl: "icons/icon128.png",
      title: "Recording stopped",
      message: "The call ended, so MacParakeet stopped and is transcribing your meeting.",
      priority: 0,
    });
  } catch (error) {
    console.warn("MacParakeet auto-stop failed:", error);
  }
}

// ---------------------------------------------------------------------------
// Event wiring
// ---------------------------------------------------------------------------

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    try {
      switch (message && message.kind) {
        case "meetingState": {
          if (sender.tab && sender.tab.id != null) {
            await handleMeetingReport(sender.tab.id, message);
          }
          sendResponse({ ok: true });
          break;
        }
        case "speakerActivity": {
          await forwardSpeakerActivity(message.events);
          sendResponse({ ok: true });
          break;
        }
        case "getStatus": {
          const settings = await getSettings();
          const meetings = await pruneStaleMeetings();
          let state = null;
          let error = null;
          try {
            state = await fetchState();
          } catch (bridgeError) {
            error = { code: bridgeError.code || "unknown", message: bridgeError.message };
          }
          await updateBadge();
          sendResponse({ ok: true, settings, meetings, state, error });
          break;
        }
        case "startRecording": {
          const state = await startRecording(message.title, message.platform, message.tabId);
          sendResponse({ ok: true, state });
          break;
        }
        case "stopRecording": {
          const state = await stopRecording();
          sendResponse({ ok: true, state });
          break;
        }
        case "launchApp": {
          const state = await launchApp();
          sendResponse({ ok: true, state });
          break;
        }
        case "setSettings": {
          await chrome.storage.sync.set(message.settings || {});
          sendResponse({ ok: true });
          break;
        }
        default:
          sendResponse({ ok: false, error: { code: "unknown_message" } });
      }
    } catch (error) {
      sendResponse({
        ok: false,
        error: { code: error.code || "unknown", message: error.message || String(error) },
      });
    }
  })();
  return true; // keep sendResponse alive across the async work
});

chrome.notifications.onButtonClicked.addListener((notificationId, buttonIndex) => {
  if (buttonIndex !== 0) return;
  startFromJoinNotification(notificationId);
});

// macOS shows Chrome notifications as banners without buttons unless the user
// enabled alert-style notifications — treat a body click as consent too.
chrome.notifications.onClicked.addListener((notificationId) => {
  startFromJoinNotification(notificationId);
});

function startFromJoinNotification(notificationId) {
  if (!notificationId.startsWith("macparakeet-join-")) return;
  const tabId = Number(notificationId.slice("macparakeet-join-".length));
  (async () => {
    chrome.notifications.clear(notificationId);
    const meetings = await getMeetings();
    const meeting = meetings[tabId];
    try {
      await startRecording(meeting ? meeting.title : null, meeting ? meeting.platform : null, tabId);
    } catch (error) {
      chrome.notifications.create("macparakeet-error", {
        type: "basic",
        iconUrl: "icons/icon128.png",
        title: "MacParakeet could not start recording",
        message: userFacingError(error),
        priority: 1,
      });
    }
  })();
}

chrome.tabs.onRemoved.addListener((tabId) => {
  (async () => {
    const meetings = await getMeetings();
    if (meetings[tabId]) {
      const wasInCall = meetings[tabId].inCall;
      delete meetings[tabId];
      await setMeetings(meetings);
      if (wasInCall) await onCallLeft(tabId);
      await updateBadge();
    }
  })();
});

// Backstop badge refresh: content scripts wake this worker every few seconds
// during a call, but nothing wakes it when a recording was started and every
// meeting tab is gone. One slow alarm keeps the REC badge from going stale.
chrome.alarms.create(STATE_POLL_ALARM, { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== STATE_POLL_ALARM) return;
  (async () => {
    const { lastState = null } = await getSession({ lastState: null });
    const meetings = await pruneStaleMeetings();
    const relevant = (lastState && lastState.recording) || Object.keys(meetings).length > 0;
    if (!relevant) return;
    try {
      await fetchState();
    } catch {
      // Host/app went away; surface as an empty badge rather than stale REC.
      await chrome.storage.session.set({ lastState: null });
    }
    await updateBadge();
  })();
});

function userFacingError(error) {
  switch (error && error.code) {
    case "host_not_installed":
      return "The native bridge is not installed. Run install.sh from integrations/chrome-extension/native-host in the MacParakeet repo.";
    case "app_unreachable":
      return "MacParakeet is not running. Open the app and try again.";
    case "bridge_disabled":
      return "The Chrome bridge is disabled. Run: macparakeet-cli config set chrome-extension on";
    case "start_rejected":
      return "MacParakeet is busy finishing another recording. Try again in a moment.";
    case "host_timeout":
    case "host_disconnected":
      return "Lost the connection to the MacParakeet bridge. Try again.";
    default:
      return (error && error.message) || "Unknown error.";
  }
}
