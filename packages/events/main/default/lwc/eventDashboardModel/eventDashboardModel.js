/**
 * Event dashboard and template rules for Event Management (EV-11), framework free so they port
 * to BarnCRM for WordPress (plan 9.9). No Salesforce imports.
 *
 * Counts are `{ ticketTypes, tracks, sessions, speakers }`. A template is the JSON in
 * `BarnEventTemplates`: `{ key, name, tracks, ticketTypes, sessions, timeline }`.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/** Whole days from now to the event's start (negative once it has started), or null. */
export function daysToGo(start, now = new Date()) {
  if (!start) {
    return null;
  }
  const from = new Date(now);
  const to = new Date(start);
  from.setHours(0, 0, 0, 0);
  to.setHours(0, 0, 0, 0);
  return Math.round((to.getTime() - from.getTime()) / DAY_MS);
}

/** The setup steps a new event goes through, each done when the event has any of its records. */
export function setupSteps(counts) {
  const c = counts || {};
  return [
    { key: 'tickets', done: (c.ticketTypes || 0) > 0 },
    { key: 'agenda', done: (c.sessions || 0) > 0 },
    { key: 'speakers', done: (c.speakers || 0) > 0 }
  ];
}

/** Whether the event has nothing a template would add to, so it can take one. */
export function canTakeTemplate(counts) {
  const c = counts || {};
  return !(c.ticketTypes || 0) && !(c.tracks || 0) && !(c.sessions || 0);
}

/** The templates in the JSON text, or none when it is missing or damaged. */
export function parseTemplates(text) {
  try {
    const parsed = JSON.parse(text);
    return Array.isArray(parsed.templates)
      ? parsed.templates.filter((t) => t && t.key && t.name)
      : [];
  } catch {
    return [];
  }
}

function atTime(startDate, day, hhmm) {
  const [hours, minutes] = String(hhmm || '00:00')
    .split(':')
    .map((part) => parseInt(part, 10) || 0);
  const out = new Date(startDate);
  out.setDate(out.getDate() + (Math.max(1, day || 1) - 1));
  out.setHours(hours, minutes, 0, 0);
  return out;
}

/**
 * What applying a template adds to an event starting at `start`: the tracks, the ticket types
 * and the sessions with real start and end times (day 1 is the event's first day, times are
 * the viewer's local time). Sessions outside the event's dates are dropped and counted in
 * `skipped`.
 */
export function planFromTemplate(template, start, end) {
  const plan = { tracks: [], ticketTypes: [], sessions: [], skipped: 0 };
  if (!template || !start) {
    return plan;
  }
  const first = new Date(start);
  const last = end ? new Date(end) : null;
  plan.tracks = (template.tracks || []).map((t, i) => ({
    name: t.name,
    sortOrder: t.sortOrder || i + 1
  }));
  plan.ticketTypes = (template.ticketTypes || []).map((t, i) => ({
    name: t.name,
    price: t.price == null ? 0 : t.price,
    quantity: t.quantity == null ? null : t.quantity,
    sortOrder: t.sortOrder || i + 1
  }));
  for (const s of template.sessions || []) {
    const from = atTime(first, s.day, s.start);
    const to = atTime(first, s.day, s.end);
    if (from < first || (last && to > last) || to <= from) {
      plan.skipped += 1;
    } else {
      plan.sessions.push({
        name: s.name,
        sessionType: s.type || 'Talk',
        room: s.room || null,
        trackName: s.track || null,
        startTime: from.toISOString(),
        endTime: to.toISOString()
      });
    }
  }
  return plan;
}

/** The planning timeline with each step's due date and whether it is past, soon or later. */
export function timelineFor(template, start, now = new Date()) {
  if (!template || !start) {
    return [];
  }
  return (template.timeline || [])
    .map((step) => {
      const due = new Date(start);
      due.setDate(due.getDate() - (step.daysBefore || 0));
      const days = daysToGo(due, now);
      let state = 'later';
      if (days < 0) {
        state = 'past';
      } else if (days <= 14) {
        state = 'soon';
      }
      return { title: step.title, due: due.toISOString(), days, state };
    })
    .sort((a, b) => a.due.localeCompare(b.due));
}
