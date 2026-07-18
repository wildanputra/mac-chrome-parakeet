// MacParakeet Meeting Recorder — in-page call detection (ADR-029).
//
// Runs only on the meeting domains declared in manifest.json. Evaluates
// layered DOM heuristics for "the user is in a call" plus a best-effort
// meeting title, and reports transitions (and a slow heartbeat) to the
// service worker. Detection is advisory: selectors rot as vendors ship UI
// changes, and a miss only means the user falls back to the popup's manual
// Record button — never a broken recording.
//
// Privacy: nothing here reads meeting content. The only data reported is
// a boolean, a platform label, and the tab's own title string; the report
// never leaves the browser except over the local native-messaging bridge.

"use strict";

(() => {
  const POLL_INTERVAL_MS = 2000;
  const HEARTBEAT_MS = 5000; // unchanged-state report cadence; SW prunes at 20s
  const SPEAKER_POLL_MS = 1000; // active-speaker sampling while in a call
  const SPEAKER_FLUSH_MS = 5000; // batch cadence for closed speaking spans
  const MAX_OPEN_SPAN_MS = 15000; // split long monologues so data flows live

  const host = location.host;

  // Strips decorations meeting pages attach to participant names
  // ("Alice (Host)", "Bob is speaking", trailing device/mute hints on the
  // next line). Returns "" when the result doesn't look like a name.
  function cleanName(raw) {
    if (!raw) return "";
    let name = String(raw).split("\n")[0].trim();
    name = name.replace(/\s*is speaking.*$/i, "");
    name = name.replace(/\s*\((you|me|host|co-host|presenter|guest|organizer)\)\s*$/i, "");
    name = name.trim();
    if (!name || name.length > 60) return "";
    return name;
  }

  // Shared fallback: walk up from a speaking indicator to the nearest
  // labeled ancestor and clean its aria-label into a name.
  function nameFromContext(el) {
    const labeled = el.closest("[aria-label]");
    return labeled ? cleanName(labeled.getAttribute("aria-label")) : "";
  }

  /** @type {{platform: string, isInCall: () => boolean, title: () => string} | null} */
  const platform = detectPlatform();
  if (!platform) return;

  function detectPlatform() {
    if (host === "meet.google.com") {
      return {
        platform: "google_meet",
        isInCall() {
          // Meeting pages have a /abc-defg-hij path; the lobby and the
          // in-call UI both live there, so require in-call-only markers:
          // the participant tiles or the call toolbar's leave region.
          if (!/^\/[a-z0-9]{3,}-[a-z0-9]{3,}-[a-z0-9]{3,}($|\?)/i.test(location.pathname + location.search) &&
              !/^\/[a-z0-9-]{10,}$/i.test(location.pathname)) {
            return false;
          }
          return !!document.querySelector(
            "[data-participant-id], [data-call-id], [data-self-name]"
          );
        },
        title() {
          // "Weekly sync – Meet" / "Meet – abc-defg-hij" variants.
          const cleaned = document.title
            .replace(/\s*[–—-]\s*Google Meet\s*$/i, "")
            .replace(/^\s*Meet\s*[–—-]\s*/i, "")
            .trim();
          return cleaned === "Google Meet" || cleaned === "Meet" ? "" : cleaned;
        },
        activeSpeakers() {
          const names = new Set();
          for (const tile of document.querySelectorAll("[data-participant-id]")) {
            const speaking = tile.querySelector(
              "[class*='speaking' i], [data-is-speaking='true'], [aria-label*='is speaking' i]"
            );
            if (!speaking) continue;
            const name =
              cleanName(tile.getAttribute("data-participant-name")) ||
              cleanName(tile.getAttribute("data-self-name")) ||
              cleanName(tile.querySelector("[data-self-name]")?.getAttribute("data-self-name")) ||
              cleanName(tile.querySelector(".notranslate")?.textContent) ||
              nameFromContext(speaking);
            if (name) names.add(name);
          }
          return [...names];
        },
      };
    }
    if (host.endsWith(".zoom.us") && location.pathname.startsWith("/wc/")) {
      return {
        platform: "zoom",
        isInCall() {
          return !!document.querySelector(
            "#wc-container-left, .meeting-app, .meeting-client, [class*='meeting-client-inner'], .footer__leave-btn, [aria-label='Leave' i]"
          );
        },
        title() {
          const cleaned = document.title.replace(/\s*[–—-]\s*Zoom\s*$/i, "").trim();
          return cleaned === "Zoom" ? "" : cleaned;
        },
        activeSpeakers() {
          const names = new Set();
          const indicators = document.querySelectorAll(
            "[class*='is-speaking' i], [class*='speaking-active' i], [class*='active-speaker' i]"
          );
          for (const indicator of indicators) {
            const container = indicator.closest("[class*='video-avatar' i], [class*='participant' i]") || indicator;
            const nameEl = container.querySelector("[class*='name' i]");
            const name = cleanName(nameEl ? nameEl.textContent : "") || nameFromContext(indicator);
            if (name) names.add(name);
          }
          return [...names];
        },
      };
    }
    if (host === "teams.microsoft.com" || host === "teams.live.com") {
      return {
        platform: "teams",
        isInCall() {
          return !!document.querySelector(
            "#hangup-button, [data-tid='hangup-main-btn'], [data-tid='call-duration'], [data-tid='call-status-container'], [data-tid='calling-screen']"
          );
        },
        title() {
          const cleaned = document.title
            .replace(/\s*\|\s*Microsoft Teams.*$/i, "")
            .replace(/^\(\d+\)\s*/, "")
            .trim();
          return cleaned === "Microsoft Teams" || cleaned === "Calendar" || cleaned === "Chat" ? "" : cleaned;
        },
        activeSpeakers() {
          const names = new Set();
          const indicators = document.querySelectorAll(
            "[data-tid*='speaking' i], [class*='is-speaking' i], [class*='speaking-indicator' i], [aria-label*='is speaking' i]"
          );
          for (const indicator of indicators) {
            const tile = indicator.closest("[data-tid*='participant' i], [data-cid*='participant' i]");
            const name =
              cleanName(tile ? tile.getAttribute("aria-label") : "") ||
              cleanName(tile ? tile.querySelector("[class*='name' i]")?.textContent : "") ||
              nameFromContext(indicator);
            if (name) names.add(name);
          }
          return [...names];
        },
      };
    }
    if (host.endsWith(".webex.com")) {
      return {
        platform: "webex",
        isInCall() {
          return !!document.querySelector(
            "[data-test='leaveMeeting'], [data-test='meeting-controls'], #meetingControls, [class*='meeting-controls'], [aria-label='Leave meeting' i]"
          );
        },
        title() {
          const cleaned = document.title.replace(/\s*[–—-]\s*(Cisco\s+)?Webex.*$/i, "").trim();
          return cleaned === "Webex" ? "" : cleaned;
        },
        activeSpeakers() {
          // Webex active-speaker markup is too volatile to chase in v1; the
          // recording still works, transcripts just keep anonymous labels.
          return [];
        },
      };
    }
    return null;
  }

  let lastInCall = null;
  let lastTitle = null;
  let lastReportAt = 0;

  function evaluateAndReport() {
    let inCall = false;
    let title = "";
    try {
      inCall = platform.isInCall();
      title = inCall ? platform.title() : "";
    } catch {
      // A vendor DOM change mid-query must never break the page.
      return;
    }
    const now = Date.now();
    const changed = inCall !== lastInCall || title !== lastTitle;
    const heartbeatDue = inCall && now - lastReportAt >= HEARTBEAT_MS;
    if (!changed && !heartbeatDue) return;
    lastInCall = inCall;
    lastTitle = title;
    lastReportAt = now;
    try {
      chrome.runtime.sendMessage(
        { kind: "meetingState", platform: platform.platform, inCall, title },
        () => void chrome.runtime.lastError // extension reloaded — ignore
      );
    } catch {
      // Extension context invalidated (update/reload). The next full page
      // load re-injects a fresh detector.
    }
  }

  evaluateAndReport();
  setInterval(evaluateAndReport, POLL_INTERVAL_MS);

  // --- Active-speaker tracking (ADR-029 speaker attribution) ---------------
  //
  // While in a call, sample which participant tiles are marked as speaking
  // and turn the samples into named time spans (wall-clock epoch ms). Spans
  // are batched to the service worker, which forwards them to the app only
  // while a MacParakeet recording is running. Selector misses degrade to "no
  // spans", which leaves transcripts with today's anonymous speaker labels.

  const openSpans = new Map(); // name -> span start (epoch ms)
  let closedSpans = [];
  let lastSpeakerFlushAt = 0;

  function sampleActiveSpeakers() {
    const now = Date.now();
    let names = [];
    if (lastInCall) {
      try {
        names = platform.activeSpeakers() || [];
      } catch {
        names = [];
      }
    }
    const speaking = new Set(names);

    for (const [name, startMs] of openSpans) {
      if (!speaking.has(name)) {
        closedSpans.push({ name, startMs, endMs: now });
        openSpans.delete(name);
      } else if (now - startMs >= MAX_OPEN_SPAN_MS) {
        // Split long monologues so spans reach the app during the call, not
        // only after the speaker finally pauses.
        closedSpans.push({ name, startMs, endMs: now });
        openSpans.set(name, now);
      }
    }
    for (const name of speaking) {
      if (!openSpans.has(name)) openSpans.set(name, now);
    }

    if (now - lastSpeakerFlushAt >= SPEAKER_FLUSH_MS) {
      flushSpeakerSpans();
    }
  }

  function flushSpeakerSpans() {
    lastSpeakerFlushAt = Date.now();
    if (closedSpans.length === 0) return;
    const events = closedSpans;
    closedSpans = [];
    try {
      chrome.runtime.sendMessage(
        { kind: "speakerActivity", events },
        () => void chrome.runtime.lastError
      );
    } catch {
      // Extension reloaded — drop the batch.
    }
  }

  setInterval(sampleActiveSpeakers, SPEAKER_POLL_MS);

  // Leaving the page (navigation or close) while in a call: try to flag the
  // call as ended so auto-stop doesn't wait for the 20s staleness prune.
  addEventListener("pagehide", () => {
    // Close and flush any speaking spans first so the tail of the meeting
    // still reaches the app.
    const now = Date.now();
    for (const [name, startMs] of openSpans) {
      closedSpans.push({ name, startMs, endMs: now });
    }
    openSpans.clear();
    flushSpeakerSpans();
    if (!lastInCall) return;
    try {
      chrome.runtime.sendMessage(
        { kind: "meetingState", platform: platform.platform, inCall: false, title: "" },
        () => void chrome.runtime.lastError
      );
    } catch {
      // Best effort only.
    }
  });
})();
