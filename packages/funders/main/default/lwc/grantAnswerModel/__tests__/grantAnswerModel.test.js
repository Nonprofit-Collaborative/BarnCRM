import { filterAnswers, preview, splitTopics, topicList, wordCount } from 'c/grantAnswerModel';

const ANSWERS = [
  {
    id: '1',
    title: 'Mission (50 words)',
    topics: 'Mission, Organization',
    text: 'We teach reading.'
  },
  {
    id: '2',
    title: 'Need statement',
    topics: 'need; mission',
    text: 'Half of third graders read below grade level.'
  },
  { id: '3', title: 'Budget narrative', topics: '', text: 'Staff costs are most of the budget.' }
];

describe('grantAnswerModel', () => {
  it('splits topics at commas and semicolons and drops blanks', () => {
    expect(splitTopics(' Mission, Need ;; Budget ')).toEqual(['Mission', 'Need', 'Budget']);
    expect(splitTopics(null)).toEqual([]);
  });

  it('lists each topic once regardless of case, sorted', () => {
    expect(topicList(ANSWERS)).toEqual(['Mission', 'need', 'Organization']);
    expect(topicList(undefined)).toEqual([]);
  });

  it('counts words', () => {
    expect(wordCount('  We teach   reading. ')).toBe(3);
    expect(wordCount('')).toBe(0);
    expect(wordCount(null)).toBe(0);
  });

  it('filters by topic without regard to case and by every search word', () => {
    expect(filterAnswers(ANSWERS, 'MISSION', '').map((a) => a.id)).toEqual(['1', '2']);
    expect(filterAnswers(ANSWERS, '', 'grade READ').map((a) => a.id)).toEqual(['2']);
    expect(filterAnswers(ANSWERS, '', 'budget').map((a) => a.id)).toEqual(['3']);
    expect(filterAnswers(ANSWERS, 'Need', 'teach')).toEqual([]);
    const [first] = filterAnswers(ANSWERS, '', '');
    expect(first.topicList).toEqual(['Mission', 'Organization']);
    expect(first.words).toBe(3);
    expect(filterAnswers(null, '', '')).toEqual([]);
  });

  it('previews long text at a word with an ellipsis', () => {
    expect(preview('short')).toBe('short');
    expect(preview('one two three four five', 12)).toBe('one two...');
    expect(preview('abcdefghijklmnop', 5)).toBe('abcde...');
  });
});
