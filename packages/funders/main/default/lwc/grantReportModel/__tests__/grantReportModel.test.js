import { indicatorLines, showNumber } from 'c/grantReportModel';

const WORDS = { periodLine: '{0}: target {1}, result {2}', notSet: 'not set' };

describe('grantReportModel', () => {
  it('shows numbers and a word for none', () => {
    expect(showNumber(null, 'not set')).toBe('not set');
    expect(showNumber('', 'x')).toBe('x');
    expect(showNumber(25)).toBe((25).toLocaleString());
    expect(showNumber('n/a')).toBe('n/a');
  });

  it('turns indicators with periods into lines and drops those with none', () => {
    const lines = indicatorLines(
      {
        indicators: [
          {
            id: 'i1',
            name: 'Readers',
            unit: 'students',
            periods: [{ name: 'Q1', target: 30, result: null }]
          },
          { id: 'i2', name: 'Empty', periods: [] },
          { id: 'i3', name: 'No unit', periods: [{ name: 'Q2', target: null, result: 4 }] }
        ]
      },
      WORDS
    );
    expect(lines.map((line) => line.title)).toEqual(['Readers (students)', 'No unit']);
    expect(lines[0].lines[0].text).toBe('Q1: target 30, result not set');
    expect(lines[1].lines[0].text).toBe('Q2: target not set, result 4');
    expect(indicatorLines(null, WORDS)).toEqual([]);
  });
});
