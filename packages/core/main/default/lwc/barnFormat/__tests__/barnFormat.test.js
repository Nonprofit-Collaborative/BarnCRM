import { format, isoDate } from 'c/barnFormat';

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
});
