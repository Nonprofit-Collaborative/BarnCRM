/**
 * The suite's status vocabulary (v1.0 visual standard): every status word maps to one of six
 * tones, and each tone to one badge theme and one icon, so success and error never differ by
 * color alone. Framework free (plan 9.9).
 *
 *   success  on, active, done, complete, current, passed, met, achieved, approved
 *   warning  attention, needs-attention, due, due-soon, expiring, review, pending
 *   error    failed, overdue, expired, not-met, rejected, blocked
 *   running  in-progress, queued (amber with a clock: work under way)
 *   info     new
 *   neutral  off, inactive, skipped, former, not-run, closed, draft (and anything unknown)
 *
 * The word only picks the look; the badge text always comes from the caller's label.
 */
const TONES = Object.freeze({
  success: { tone: 'success', themeClass: 'slds-theme_success', iconName: 'utility:success' },
  warning: { tone: 'warning', themeClass: 'slds-theme_warning', iconName: 'utility:warning' },
  error: { tone: 'error', themeClass: 'slds-theme_error', iconName: 'utility:error' },
  running: { tone: 'running', themeClass: 'slds-theme_warning', iconName: 'utility:clock' },
  info: { tone: 'info', themeClass: '', iconName: 'utility:info' },
  neutral: { tone: 'neutral', themeClass: '', iconName: '' }
});

const ALIASES = Object.freeze({
  on: 'success',
  active: 'success',
  done: 'success',
  complete: 'success',
  completed: 'success',
  current: 'success',
  passed: 'success',
  met: 'success',
  achieved: 'success',
  approved: 'success',
  attention: 'warning',
  'needs-attention': 'warning',
  due: 'warning',
  'due-soon': 'warning',
  expiring: 'warning',
  review: 'warning',
  pending: 'warning',
  failed: 'error',
  overdue: 'error',
  expired: 'error',
  'not-met': 'error',
  rejected: 'error',
  blocked: 'error',
  'in-progress': 'running',
  queued: 'running',
  new: 'info',
  off: 'neutral',
  inactive: 'neutral',
  skipped: 'neutral',
  former: 'neutral',
  'not-run': 'neutral',
  closed: 'neutral',
  draft: 'neutral',
  // Older kit callers passed "inverse"; the standard never uses an inverse (black) badge.
  inverse: 'neutral'
});

function normalize(status) {
  return String(status || '')
    .trim()
    .toLowerCase()
    .replace(/[\s_]+/g, '-');
}

/** `{ tone, themeClass, iconName }` for a status word; neutral when the word is unknown. */
export function statusFor(status) {
  const word = normalize(status);
  const own = (map, key) => Object.prototype.hasOwnProperty.call(map, key);
  if (own(TONES, word)) {
    return TONES[word];
  }
  return TONES[own(ALIASES, word) ? ALIASES[word] : 'neutral'];
}

export { TONES, ALIASES };
