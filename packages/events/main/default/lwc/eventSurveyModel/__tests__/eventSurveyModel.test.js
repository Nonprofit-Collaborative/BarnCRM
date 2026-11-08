import { average, parseAnswers, responseRate, summarize } from '../eventSurveyModel';

const QUESTIONS = [
  { key: 'rating', label: 'How was it?', kind: 'number' },
  { key: 'again', label: 'Come again?', kind: 'picklist' },
  { key: 'comment', label: 'Anything else?', kind: 'textarea' }
];

const response = (name, answers) => ({ name, answers: JSON.stringify(answers) });

describe('eventSurveyModel', () => {
  it('reads answers and treats anything unreadable as none', () => {
    expect(parseAnswers('{"a":1}')).toEqual({ a: 1 });
    expect(parseAnswers('not json')).toEqual({});
    expect(parseAnswers('[1,2]')).toEqual({});
    expect(parseAnswers(null)).toEqual({});
  });

  it('averages to one decimal and gives null for nothing', () => {
    expect(average([4, 5, 5])).toBe(4.7);
    expect(average([])).toBeNull();
  });

  it('summarises numbers, choices and comments per question in the form order', () => {
    const summary = summarize(QUESTIONS, [
      response('Sam Lee', { rating: 5, again: 'Yes', comment: 'Great' }),
      response('Ray Cho', { rating: '3', again: 'No', comment: '  ' }),
      response('Amy Fox', { rating: 4, again: 'Yes' })
    ]);
    expect(summary.map((entry) => entry.key)).toEqual(['rating', 'again', 'comment']);
    expect(summary[0]).toMatchObject({
      type: 'number',
      answered: 3,
      average: 4,
      lowest: 3,
      highest: 5
    });
    expect(summary[1].options).toEqual([
      { value: 'Yes', count: 2, percent: 67 },
      { value: 'No', count: 1, percent: 33 }
    ]);
    expect(summary[2]).toMatchObject({ type: 'text', answered: 1, more: 0 });
    expect(summary[2].texts).toEqual([{ who: 'Sam Lee', text: 'Great' }]);
  });

  it('counts a checkbox as Yes and No and shows an unanswered question with zero', () => {
    const summary = summarize(
      [
        { key: 'ok', label: 'Fine?', kind: 'checkbox' },
        { key: 'x', label: 'Nobody', kind: 'picklist' }
      ],
      [response('A', { ok: true }), response('B', { ok: false })]
    );
    expect(summary[0].options.map((option) => option.value).sort()).toEqual(['No', 'Yes']);
    expect(summary[1]).toMatchObject({ answered: 0, type: 'text' });
  });

  it('lists at most twenty comments and says how many more there are', () => {
    const many = Array.from({ length: 23 }, (_, index) =>
      response(`P${index}`, { comment: `c${index}` })
    );
    const entry = summarize([QUESTIONS[2]], many)[0];
    expect(entry.texts).toHaveLength(20);
    expect(entry.more).toBe(3);
  });

  it('handles no questions and no responses', () => {
    expect(summarize(undefined, undefined)).toEqual([]);
    expect(summarize(QUESTIONS, [])[0]).toMatchObject({ answered: 0, average: null });
  });

  it('works out the response rate from those sent, or from those who attended', () => {
    expect(responseRate(3, 12, 20)).toBe(25);
    expect(responseRate(3, 0, 6)).toBe(50);
    expect(responseRate(9, 4, 4)).toBe(100);
    expect(responseRate(0, 0, 0)).toBeNull();
  });
});
