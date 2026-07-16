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

  const host = location.host;

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

  // Leaving the page (navigation or close) while in a call: try to flag the
  // call as ended so auto-stop doesn't wait for the 20s staleness prune.
  addEventListener("pagehide", () => {
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
