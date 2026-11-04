import { initialsOf, opensElsewhere, recordHref } from 'c/recordRows';

describe('c/recordRows', () => {
  it('takes the first letters of the first and last words', () => {
    expect(initialsOf('Maria del Carmen Garcia')).toBe('MG');
    expect(initialsOf('  cher ')).toBe('C');
    expect(initialsOf('')).toBe('');
    expect(initialsOf(null)).toBe('');
  });

  it('links to the plain record path', () => {
    expect(recordHref('0031000000000001AA')).toBe('/0031000000000001AA');
    expect(recordHref(undefined)).toBeUndefined();
  });

  it('leaves a modifier or middle click to the browser', () => {
    expect(opensElsewhere({ button: 0 })).toBe(false);
    expect(opensElsewhere({ button: 1 })).toBe(true);
    expect(opensElsewhere({ button: 0, metaKey: true })).toBe(true);
    expect(opensElsewhere(undefined)).toBe(false);
  });
});
