import {
  escapeHtml,
  indicatorLines,
  mergeReport,
  mergeTokens,
  outcomeResults,
  reportDocument,
  requirementTable,
  showDate,
  showMoney,
  showNumber
} from 'c/grantReportModel';

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

  it('escapes HTML and shows dates and amounts', () => {
    expect(escapeHtml('<a href="x">Tom & Jo\'s</a>')).toBe(
      '&lt;a href=&quot;x&quot;&gt;Tom &amp; Jo&#39;s&lt;/a&gt;'
    );
    expect(escapeHtml(null)).toBe('');
    expect(showDate('2026-11-02', 'en-US')).toBe('11/2/2026');
    expect(showDate('', 'en-US')).toBe('');
    expect(showDate('soon', 'en-US')).toBe('soon');
    expect(showMoney(25000, 'USD', 'en-US')).toBe('$25,000.00');
    expect(showMoney(null, 'USD', 'en-US')).toBe('');
  });

  it('merges known tokens once and keeps unknown ones', () => {
    expect(mergeTokens('{A} and {B} and {Other}', { A: '{B}', B: 'b' })).toBe(
      '{B} and b and {Other}'
    );
    expect(mergeTokens(null, {})).toBe('');
  });

  it('builds the requirement table and outcome results', () => {
    expect(requirementTable([], {})).toBe('');
    const table = requirementTable(
      [
        {
          name: 'Final <report>',
          type: 'Narrative Report',
          dueDate: '2027-01-31',
          status: 'Submitted'
        }
      ],
      { name: 'Requirement Name' },
      'en-US'
    );
    expect(table).toContain('<th>Requirement Name</th><th>type</th>');
    expect(table).toContain('<td>Final &lt;report&gt;</td>');
    expect(table).toContain('<td>1/31/2027</td>');
    const results = outcomeResults(
      [
        {
          name: 'Reading',
          model: 'Literacy',
          indicators: [{ name: 'Readers', periods: [{ name: 'Q1', target: 30, result: 28 }] }]
        },
        { name: 'Bare', indicators: [] }
      ],
      WORDS
    );
    expect(results).toContain('<h3>Literacy: Reading</h3><ul><li>Readers<ul><li>Q1: target 30');
    expect(results).toContain('<h3>Bare</h3>');
    expect(outcomeResults(null, WORDS)).toBe('');
  });

  it('merges a whole report, escaping the grant values', () => {
    const body = mergeReport(
      '<h1>{GrantName}</h1><p>{AmountAwarded} {AwardStartDate}</p><p>{Purpose}</p>{RequirementTable}{OutcomeResults}{Nope}',
      {
        grant: {
          GrantName: 'Reading <Grant>',
          AmountAwarded: 1500,
          AwardStartDate: '2026-01-01',
          Purpose: 'Line one\nLine two'
        },
        requirements: [],
        outcomes: [],
        currencyCode: 'USD'
      },
      WORDS,
      'en-US'
    );
    expect(body).toBe(
      '<h1>Reading &lt;Grant&gt;</h1><p>$1,500.00 1/1/2026</p><p>Line one<br/>Line two</p>{Nope}'
    );
    expect(reportDocument('A & B', '<p>x</p>')).toContain('<title>A &amp; B</title>');
    expect(reportDocument('A', '<p>x</p>')).toContain('<body><p>x</p></body>');
  });
});
