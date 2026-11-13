/**
 * Badges and sign-in sheets, with no framework in it (EV-17, plan Section 9.9): the badge
 * layouts, narrowing the people to print, and the print pages as plain HTML text with their own
 * print CSS. The page is opened in a new browser window and printed there, so nothing leaves the
 * browser and no PDF library is needed. Every value put in the page is escaped.
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module. An attendee
 * is { id, name, organization, ticketName, tableName }.
 */
import { escapeHtml } from 'c/barnFormat';

/** The badge sizes, in inches. `value` is the key a layout picker holds. */
export const LAYOUTS = Object.freeze([
  { value: 'large', width: 4, height: 3, nameSize: 28 },
  { value: 'standard', width: 4, height: 2, nameSize: 24 },
  { value: 'compact', width: 3.375, height: 2.33, nameSize: 20 }
]);

export const DEFAULT_LAYOUT = 'standard';

/** Blank lines added to a sign-in sheet for people who were not registered. */
export const BLANK_ROWS = 10;

/** The layout for a key, the default when the key is unknown. */
export function layoutFor(value) {
  return (
    LAYOUTS.find((layout) => layout.value === value) ||
    LAYOUTS.find((layout) => layout.value === DEFAULT_LAYOUT)
  );
}

/** Text safe to put inside HTML, from the shared kit. */
export { escapeHtml };

/** The attendees whose name or organization holds the term, and who hold the ticket named. */
export function selectAttendees(attendees, term, ticketName) {
  const text = String(term || '')
    .trim()
    .toLowerCase();
  return (attendees || []).filter((attendee) => {
    if (ticketName && attendee.ticketName !== ticketName) {
      return false;
    }
    return (
      !text || `${attendee.name || ''} ${attendee.organization || ''}`.toLowerCase().includes(text)
    );
  });
}

/** The distinct ticket names among the attendees, sorted. */
export function ticketNames(attendees) {
  return [
    ...new Set((attendees || []).map((attendee) => attendee.ticketName).filter(Boolean))
  ].sort();
}

const PAGE_STYLE = `
  @page { size: letter; margin: 0.5in; }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #000; margin: 0; }
  h1 { font-size: 18pt; margin: 0 0 4pt; }
  p.meta { margin: 0 0 12pt; color: #333; }
`;

function pageHtml(title, style, body) {
  return `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(title)}</title><style>${PAGE_STYLE}${style}</style></head><body>${body}</body></html>`;
}

/**
 * The badge page. `badges` is a list of { name, title, organization, ticketName, qr } where qr is an
 * image address (a data address made in the browser) or empty. `show` has organization, ticket
 * and qr switches.
 */
export function badgePageHtml(title, layoutValue, badges, show) {
  const layout = layoutFor(layoutValue);
  const options = show || {};
  const style = `
    .sheet { display: flex; flex-wrap: wrap; }
    .badge { width: ${layout.width}in; height: ${layout.height}in; padding: 0.2in; border: 1px dashed #999;
      display: flex; align-items: center; justify-content: space-between; gap: 0.15in; overflow: hidden;
      page-break-inside: avoid; break-inside: avoid; }
    .text { flex: 1 1 auto; min-width: 0; }
    .name { font-size: ${layout.nameSize}pt; font-weight: bold; line-height: 1.1; overflow-wrap: anywhere; }
    .title { font-size: 12pt; font-style: italic; margin-top: 4pt; overflow-wrap: anywhere; }
    .org { font-size: 13pt; margin-top: 6pt; overflow-wrap: anywhere; }
    .ticket { font-size: 11pt; margin-top: 6pt; text-transform: uppercase; letter-spacing: 0.04em; color: #333; }
    .qr { flex: 0 0 auto; width: ${Math.min(1.1, layout.height - 0.6).toFixed(2)}in; height: auto; }
    @media screen { body { padding: 0.25in; } }
  `;
  const cards = (badges || [])
    .map((badge) => {
      const org =
        options.organization && badge.organization
          ? `<div class="org">${escapeHtml(badge.organization)}</div>`
          : '';
      // EV-26: a Badge Title prints under the name only when it is set.
      const titleLine = badge.title ? `<div class="title">${escapeHtml(badge.title)}</div>` : '';
      const ticket =
        options.ticket && badge.ticketName
          ? `<div class="ticket">${escapeHtml(badge.ticketName)}</div>`
          : '';
      const qr =
        options.qr && badge.qr ? `<img class="qr" src="${escapeHtml(badge.qr)}" alt="">` : '';
      return `<div class="badge"><div class="text"><div class="name">${escapeHtml(badge.name)}</div>${titleLine}${org}${ticket}</div>${qr}</div>`;
    })
    .join('');
  return pageHtml(title, style, `<div class="sheet">${cards}</div>`);
}

/**
 * The sign-in sheet: a heading, then one line per person with a column to sign, and
 * `blankRows` empty lines for people who were not registered.
 */
export function signInPageHtml(heading, subheading, rows, columns, blankRows) {
  const style = `
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #000; padding: 6pt 8pt; text-align: left; font-size: 11pt; }
    th { background: #eee; }
    td.sign { width: 35%; }
    tr { page-break-inside: avoid; break-inside: avoid; }
    thead { display: table-header-group; }
    tr.blank td { height: 28pt; }
  `;
  const head = `<tr><th>${escapeHtml(columns.name)}</th><th>${escapeHtml(columns.organization)}</th><th>${escapeHtml(columns.ticket)}</th><th class="sign">${escapeHtml(columns.signature)}</th></tr>`;
  const lines = (rows || [])
    .map(
      (row) =>
        `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.organization)}</td><td>${escapeHtml(row.ticketName)}</td><td class="sign"></td></tr>`
    )
    .join('');
  const blanks = '<tr class="blank"><td></td><td></td><td></td><td class="sign"></td></tr>'.repeat(
    Math.max(Number(blankRows) || 0, 0)
  );
  return pageHtml(
    heading,
    style,
    `<h1>${escapeHtml(heading)}</h1><p class="meta">${escapeHtml(subheading)}</p><table><thead>${head}</thead><tbody>${lines}${blanks}</tbody></table>`
  );
}

/**
 * Session rating codes (EV-27): one half page per session with its name, time and room, a call to
 * rate and the QR code of its rating link. `sessions` is a list of { name, whenText, room, qr }.
 */
export function ratingCodesPageHtml(title, prompt, sessions) {
  const style = `
    .code { height: 4.8in; display: flex; flex-direction: column; align-items: center; justify-content: center;
      text-align: center; border-bottom: 1px dashed #999; page-break-inside: avoid; break-inside: avoid; }
    .code h2 { font-size: 22pt; margin: 0 0 6pt; overflow-wrap: anywhere; }
    .code p { font-size: 13pt; margin: 0 0 6pt; }
    .code img { width: 2.4in; height: auto; margin-top: 8pt; }
  `;
  const pages = (sessions || [])
    .map(
      (session) =>
        `<div class="code"><h2>${escapeHtml(session.name)}</h2><p>${escapeHtml(
          [session.whenText, session.room].filter(Boolean).join(', ')
        )}</p><p><strong>${escapeHtml(prompt)}</strong></p>${
          session.qr ? `<img src="${escapeHtml(session.qr)}" alt="">` : ''
        }</div>`
    )
    .join('');
  return pageHtml(title, style, pages);
}
