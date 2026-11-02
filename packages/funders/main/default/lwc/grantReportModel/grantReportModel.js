/**
 * Funder reporting logic, with no framework in it (L-06 and F-06, canonical model 29ZI R-GQ6,
 * ADR-0163 `0163-funders-reporting-links.md`, plan Section 9.9). Plain JavaScript in and out, so a
 * WordPress block or Node can use the same module. Dates arrive as ISO date strings.
 */

/** The tokens a funder report template may use (R-FT2), each a plain value but the last two. */
export const VALUE_TOKENS = [
  'OrganizationName',
  'Today',
  'GrantName',
  'FunderName',
  'FunderContactName',
  'OwnerName',
  'Stage',
  'FundingSource',
  'AmountRequested',
  'AmountAwarded',
  'ApplicationDeadline',
  'AwardStartDate',
  'AwardEndDate',
  'Purpose',
  'ProgramName',
  'AssistanceListingNumber',
  'AwardNumber',
  'FederalAgency'
];
const MONEY_TOKENS = new Set(['AmountRequested', 'AmountAwarded']);
const DATE_TOKENS = new Set(['Today', 'ApplicationDeadline', 'AwardStartDate', 'AwardEndDate']);
const TOKEN = /\{(\w+)\}/g;

/** Text made safe inside HTML. */
export function escapeHtml(value) {
  return String(value === null || value === undefined ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** An ISO date ("2026-11-02") in the locale, read as a calendar day; blank when there is none. */
export function showDate(iso, locale) {
  if (!iso) {
    return '';
  }
  const parsed = new Date(`${String(iso).slice(0, 10)}T00:00:00Z`);
  return Number.isNaN(parsed.getTime())
    ? String(iso)
    : parsed.toLocaleDateString(locale, { timeZone: 'UTC' });
}

/** An amount in the currency and locale; blank when there is none. */
export function showMoney(value, currencyCode, locale) {
  if (value === null || value === undefined || value === '') {
    return '';
  }
  try {
    return Number(value).toLocaleString(locale, {
      style: 'currency',
      currency: currencyCode || 'USD'
    });
  } catch {
    return Number(value).toLocaleString(locale);
  }
}

/**
 * Replaces each known `{Token}` in one pass (R-FT2): a merged value that looks like a token is
 * never merged again, and unknown text in braces stays as typed.
 *
 * @param {string} body the template's HTML
 * @param {Object<string, string>} html each token's HTML, already escaped
 */
export function mergeTokens(body, html) {
  const known = (name) => Object.prototype.hasOwnProperty.call(html, name);
  return String(body || '').replace(TOKEN, (whole, name) => (known(name) ? html[name] : whole));
}

/** A requirement table as HTML, or empty when the grant has none. */
export function requirementTable(requirements, labels, locale) {
  const rows = requirements || [];
  if (rows.length === 0) {
    return '';
  }
  const heads = ['name', 'type', 'dueDate', 'status', 'submittedDate'];
  const head = heads.map((key) => `<th>${escapeHtml((labels || {})[key] || key)}</th>`).join('');
  const body = rows
    .map((row) => {
      const cells = [
        row.name,
        row.type,
        showDate(row.dueDate, locale),
        row.status,
        showDate(row.submittedDate, locale)
      ];
      return `<tr>${cells.map((cell) => `<td>${escapeHtml(cell)}</td>`).join('')}</tr>`;
    })
    .join('');
  return `<table class="requirements"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}

/** Each linked outcome with its indicator lines as HTML, or empty when there are none. */
export function outcomeResults(outcomes, words) {
  return (outcomes || [])
    .map((outcome) => {
      const indicators = indicatorLines(outcome, words)
        .map(
          (indicator) =>
            `<li>${escapeHtml(indicator.title)}<ul>${indicator.lines
              .map((line) => `<li>${escapeHtml(line.text)}</li>`)
              .join('')}</ul></li>`
        )
        .join('');
      const title = outcome.model ? `${outcome.model}: ${outcome.name}` : outcome.name;
      return `<h3>${escapeHtml(title)}</h3>${indicators ? `<ul>${indicators}</ul>` : ''}`;
    })
    .join('');
}

/**
 * The merged report body (R-FT2).
 *
 * @param {string} body the template's HTML
 * @param {object} data `{grant, requirements, requirementLabels, outcomes, currencyCode}` from the server
 * @param {{periodLine: string, notSet: string}} words for the outcome lines
 * @param {string} [locale] the locale to write amounts and dates in
 */
export function mergeReport(body, data, words, locale) {
  const grant = (data && data.grant) || {};
  const html = {};
  VALUE_TOKENS.forEach((name) => {
    const value = grant[name];
    let text;
    if (MONEY_TOKENS.has(name)) {
      text = showMoney(value, data.currencyCode, locale);
    } else if (DATE_TOKENS.has(name)) {
      text = showDate(value, locale);
    } else {
      text = value === null || value === undefined ? '' : String(value);
    }
    html[name] = escapeHtml(text).replace(/\r?\n/g, '<br/>');
  });
  html.RequirementTable = requirementTable(
    data && data.requirements,
    data && data.requirementLabels,
    locale
  );
  html.OutcomeResults = outcomeResults(data && data.outcomes, words);
  return mergeTokens(body, html);
}

/** The whole printable HTML document around a merged body. */
export function reportDocument(title, body) {
  return [
    '<!DOCTYPE html><html><head><meta charset="utf-8">',
    `<title>${escapeHtml(title)}</title>`,
    '<style>body{font-family:sans-serif;font-size:12pt;max-width:48em;margin:2em auto;line-height:1.4}',
    'table{border-collapse:collapse;margin:0.5em 0}th,td{border:1px solid #999;padding:4px 8px;text-align:left;vertical-align:top}',
    '@media print{body{margin:0}}</style></head><body>',
    body,
    '</body></html>'
  ].join('');
}

/** A number as the person's locale writes it, or the `notSet` word when there is none. */
export function showNumber(value, notSet = '') {
  if (value === null || value === undefined || value === '') {
    return notSet;
  }
  const number = Number(value);
  return Number.isNaN(number) ? String(value) : number.toLocaleString();
}

/**
 * The indicators of a linked outcome as lines to show: the indicator name with its unit, then one
 * line per period in the award period.
 *
 * @param {object} outcome `{indicators: [{id, name, unit, periods: [{name, target, result}]}]}`
 * @param {{periodLine: string, notSet: string}} words `periodLine` holds {0} period, {1} target
 *   and {2} result
 * @returns {{key: string, title: string, lines: {key: string, text: string}[]}[]} indicators with
 *   at least one period
 */
export function indicatorLines(outcome, words) {
  const indicators = (outcome && outcome.indicators) || [];
  return indicators
    .filter((indicator) => (indicator.periods || []).length > 0)
    .map((indicator) => ({
      key: indicator.id,
      title: indicator.unit ? `${indicator.name} (${indicator.unit})` : indicator.name,
      lines: indicator.periods.map((period, index) => ({
        key: `${indicator.id}-${index}`,
        text: [
          period.name,
          showNumber(period.target, words.notSet),
          showNumber(period.result, words.notSet)
        ].reduce((text, value, position) => text.replace(`{${position}}`, value), words.periodLine)
      }))
    }));
}
