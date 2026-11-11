/**
 * Scholarships' shared logic in plain JavaScript (plan Section 9.9): a review's weighted total as
 * the reviewer types (Apex recomputes it on save, R-SG6) and the disbursement export as CSV.
 */

/** Each criterion's score, between 0 and its max, times its weight, added together. */
export function weightedTotal(criteria, scores) {
  let total = 0;
  (criteria || []).forEach((criterion) => {
    const given = Number(scores && scores[criterion.key]);
    const max = Number(criterion.max ?? 10);
    const capped = Number.isFinite(given) ? Math.max(0, Math.min(given, max)) : 0;
    total += capped * Number(criterion.weight ?? 1);
  });
  return Math.round(total * 100) / 100;
}

/** One CSV cell: quoted when it holds a comma, quote or line break; a leading = + - @ is neutralized. */
export function csvCell(value) {
  if (value === null || value === undefined) {
    return '';
  }
  let text = String(value);
  if (/^[=+\-@]/.test(text) && Number.isNaN(Number(text))) {
    text = "'" + text;
  }
  return /[",\r\n]/.test(text) ? '"' + text.replace(/"/g, '""') + '"' : text;
}

/** The export's columns: the row key and its heading. */
export const EXPORT_COLUMNS = [
  ['name', 'Disbursement'],
  ['award', 'Award'],
  ['recipient', 'Recipient'],
  ['payee', 'Payee'],
  ['amount', 'Amount'],
  ['status', 'Status'],
  ['scheduled', 'Scheduled Date'],
  ['paid', 'Paid Date'],
  ['method', 'Payment Method'],
  ['reference', 'Reference'],
  ['program', 'Program'],
  ['cycle', 'Cycle']
];

/** Rows as CSV text with a heading line. */
export function toCsv(rows, columns = EXPORT_COLUMNS) {
  const lines = [columns.map(([, heading]) => csvCell(heading)).join(',')];
  (rows || []).forEach((row) => {
    lines.push(columns.map(([key]) => csvCell(row[key])).join(','));
  });
  return lines.join('\r\n') + '\r\n';
}
