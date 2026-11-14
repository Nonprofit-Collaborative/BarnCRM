import {
  badgeWord,
  csvCell,
  escapeHtml,
  format,
  formatDate,
  isoDate,
  percent,
  utcIsoDate
} from 'c/barnFormat';

describe('c/barnFormat', () => {
  it('fills placeholders in order, more than once', () => {
    expect(format('{0} of {1}', 'one', 'two')).toBe('one of two');
    expect(format('{0} and {0} of {1}', 'a', 2)).toBe('a and a of 2');
  });

  it('reads a missing label as empty and leaves text without placeholders alone', () => {
    expect(format(undefined, 'a')).toBe('');
    expect(format(null)).toBe('');
    expect(format('No placeholders')).toBe('No placeholders');
  });

  it('keeps a placeholder with no value and empties a null one', () => {
    expect(format('{0} {1}', 'a')).toBe('a {1}');
    expect(format('[{0}]', null)).toBe('[]');
    expect(format('[{0}]', undefined)).toBe('[]');
    expect(format('{0}', 0)).toBe('0');
    expect(format('{0}', false)).toBe('false');
  });

  it('never fills a placeholder that a value brought in', () => {
    expect(format('{0} {1}', '{1}', 'b')).toBe('{1} b');
  });

  it('writes a local date as YYYY-MM-DD', () => {
    expect(isoDate(new Date(2026, 0, 5))).toBe('2026-01-05');
    expect(isoDate(new Date(2026, 11, 31, 23, 59))).toBe('2026-12-31');
    expect(isoDate()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('formats a calendar day in the locale, keeping text that is not a date', () => {
    expect(formatDate('2026-03-01', 'en-US')).toBe('Mar 1, 2026');
    expect(formatDate(null, 'en-US')).toBeNull();
    expect(formatDate('soon', 'en-US')).toBe('soon');
  });

  it('escapes every HTML special character and reads null as empty text', () => {
    expect(escapeHtml(`<a href="x">Tom & Jo's</a>`)).toBe(
      '&lt;a href=&quot;x&quot;&gt;Tom &amp; Jo&#39;s&lt;/a&gt;'
    );
    expect(escapeHtml(null)).toBe('');
    expect(escapeHtml(0)).toBe('0');
  });

  it('writes a time as its UTC calendar day', () => {
    expect(utcIsoDate(Date.UTC(2026, 10, 12, 23, 30))).toBe('2026-11-12');
  });

  it('rounds a share to a whole percent and reads no whole as 0', () => {
    expect(percent(1, 3)).toBe(33);
    expect(percent(2, 3)).toBe(67);
    expect(percent(5, 0)).toBe(0);
    expect(percent(null, 4)).toBe(0);
    expect(percent(1, -4)).toBe(0);
  });

  it('gives the badge word a map names, else neutral', () => {
    expect(badgeWord({ Open: 'active' }, 'Open')).toBe('active');
    expect(badgeWord({ Open: 'active' }, 'Other')).toBe('neutral');
    expect(badgeWord(null, 'Open')).toBe('neutral');
  });

  it('quotes a CSV cell and keeps a spreadsheet from running it', () => {
    expect(csvCell('a,b')).toBe('"a,b"');
    expect(csvCell('say "hi"')).toBe('"say ""hi"""');
    expect(csvCell('=SUM(A1)')).toBe("'=SUM(A1)");
    expect(csvCell('-5')).toBe('-5');
    expect(csvCell(-5)).toBe('-5');
    expect(csvCell(null)).toBe('');
  });
});
