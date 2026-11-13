/**
 * The text "Copy for Bug Report" puts on the clipboard (QA review Q10), framework free (plan
 * 9.9): no lightning or @salesforce imports, the words come in from the caller.
 *
 * Redaction is by keeping, not by removing: the entry's message and any record are never read,
 * and from the technical detail only three things are kept: Salesforce error codes
 * (FIELD_CUSTOM_VALIDATION_EXCEPTION), exception type names (System.DmlException) and stack
 * lines (Class.GiftService.save: line 120, column 1). None of them can hold a name, an email
 * or a field value, so the text is safe to paste into a public GitHub issue.
 */

const ERROR_CODE = /\b[A-Z][A-Z0-9]+(?:_[A-Z0-9]+){1,}\b/g;
const EXCEPTION_TYPE = /\b(?:[A-Z]\w*\.)*[A-Z]\w*Exception\b/g;
const STACK_LINE = /^\s*((?:Class|Trigger|AnonymousBlock)\.[\w.]+: line \d+, column \d+)\s*$/gm;
const MAX_STACK_LINES = 15;

function unique(values) {
  return [...new Set(values)];
}

/** The error codes, exception types and stack lines in a technical detail, nothing else. */
export function safeParts(technicalDetail) {
  const text = typeof technicalDetail === 'string' ? technicalDetail : '';
  const stack = [];
  for (const match of text.matchAll(STACK_LINE)) {
    stack.push(match[1]);
  }
  return {
    codes: unique(text.match(ERROR_CODE) || []),
    exceptions: unique(text.match(EXCEPTION_TYPE) || []),
    stack: unique(stack).slice(0, MAX_STACK_LINES)
  };
}

/** A moment as YYYY-MM-DD HH:MM UTC, or '' when there is none. */
export function utcMinute(value) {
  const when = value ? new Date(value) : null;
  if (!when || Number.isNaN(when.getTime())) {
    return '';
  }
  return `${when.toISOString().replace('T', ' ').slice(0, 16)} UTC`;
}

/**
 * The bug report text for one Error Log entry.
 * @param {object} entry from ErrorLogController.getBugReport: context, severity, occurredAt,
 *   occurrences, objectName, technicalDetail (absent for someone who may not read it)
 * @param {object} words heading, where, object, severity, when, times, codes, stack, none,
 *   noDetail: the help catalog's words
 * @returns {string} plain text, one item a line
 */
export function bugReportText(entry, words) {
  const source = entry || {};
  const parts = safeParts(source.technicalDetail);
  const line = (label, value) =>
    `${label}: ${value === undefined || value === null || value === '' ? words.none : value}`;
  const lines = [
    words.heading,
    line(words.where, source.context),
    line(words.object, source.objectName),
    line(words.severity, source.severity),
    line(words.when, utcMinute(source.occurredAt)),
    line(words.times, source.occurrences || 1),
    line(words.codes, [...parts.exceptions, ...parts.codes].join(', '))
  ];
  if (parts.stack.length) {
    lines.push(`${words.stack}:`, ...parts.stack.map((frame) => `  ${frame}`));
  } else if (!source.technicalDetail) {
    lines.push(words.noDetail);
  }
  return lines.join('\n');
}
