// Slows password guessing. Keyed on the username, not the IP: behind the proxy the client controls the IP header, so an
// IP limit could be sidestepped. Failures expire after a short window, so nobody is locked out for good (an attacker can
// still make a known username wait a few minutes, which is the price of not trusting the IP).
const WINDOW_MS = parseInt(process.env.LOGIN_RATE_WINDOW_MS, 10) || 10 * 60 * 1000;
const MAX_FAILURES = parseInt(process.env.LOGIN_RATE_MAX, 10) || 10;
const MAX_TRACKED = 5000;

const failures = new Map(); // lowercase username -> timestamps of recent failures

const key = (username) => String(username || '').toLowerCase().slice(0, 100);

function recent(name, now = Date.now()) {
  return (failures.get(name) || []).filter((t) => now - t < WINDOW_MS);
}

function isLimited(username, now = Date.now()) {
  return recent(key(username), now).length >= MAX_FAILURES;
}

function recordFailure(username, now = Date.now()) {
  const name = key(username);
  const list = recent(name, now);
  list.push(now);
  failures.set(name, list);
  if (failures.size > MAX_TRACKED) {
    for (const [k, v] of failures) {
      if (!v.some((t) => now - t < WINDOW_MS)) failures.delete(k);
    }
  }
}

function clear(username) {
  failures.delete(key(username));
}

module.exports = { isLimited, recordFailure, clear, WINDOW_MS, MAX_FAILURES };
