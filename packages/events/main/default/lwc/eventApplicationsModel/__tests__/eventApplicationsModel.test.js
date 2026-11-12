import {
  averageText,
  blinded,
  canCompare,
  criteriaValid,
  isUndecided,
  isValidScore,
  matrixRows,
  roundScore,
  scoreOptions,
  scoresOf,
  statusWord,
  weightedScore
} from 'c/eventApplicationsModel';

/* The same cases EventProposalReviewTest checks in Apex (R-SA6, R-SA7). */
const CRITERIA = [
  { label: 'Relevance', weight: 2 },
  { label: 'Clarity', weight: 1 }
];

describe('eventApplicationsModel', () => {
  it('lets only Submitted and In Review applications be scored or decided', () => {
    expect(isUndecided('Submitted')).toBe(true);
    expect(isUndecided('In Review')).toBe(true);
    expect(isUndecided('Accepted')).toBe(false);
    expect(isUndecided('Declined')).toBe(false);
    expect(isUndecided('Withdrawn')).toBe(false);
  });

  it('accepts only whole scores from 1 to 5', () => {
    expect([1, 3, 5, '4'].every(isValidScore)).toBe(true);
    expect([0, 6, 2.5, 'x', null, undefined].some(isValidScore)).toBe(false);
  });

  it('offers the five scores as text options', () => {
    expect(scoreOptions().map((option) => option.value)).toEqual(['1', '2', '3', '4', '5']);
  });

  it('writes an average to one decimal with the review count, empty before a review', () => {
    expect(averageText(4, 3)).toBe('4.0 (3)');
    expect(averageText(3.666, 3)).toBe('3.7 (3)');
    expect(averageText(null, 0)).toBe('');
    expect(averageText(undefined, 2)).toBe('');
  });

  it('gives each status a badge word and an unknown one a neutral look', () => {
    expect(statusWord('Accepted')).toBe('approved');
    expect(statusWord('Declined')).toBe('rejected');
    expect(statusWord('Submitted')).toBe('new');
    expect(statusWord('Mystery')).toBe('neutral');
  });

  it('weights criteria scores to two decimals and rounds halves up', () => {
    expect(weightedScore(CRITERIA, { Relevance: 5, Clarity: 2 })).toBe(4);
    expect(weightedScore(CRITERIA, { Relevance: 4, Clarity: 5 })).toBe(4.33);
    expect(weightedScore(CRITERIA, { Relevance: 3, Clarity: 2 })).toBe(2.67);
    expect(weightedScore(CRITERIA, { Relevance: 5 })).toBeNull();
    expect(weightedScore(CRITERIA, { Relevance: 6, Clarity: 1 })).toBeNull();
    expect(weightedScore([], {})).toBeNull();
    expect(roundScore(4.33)).toBe(4);
    expect(roundScore(2.5)).toBe(3);
    expect(roundScore(null)).toBeNull();
  });

  it('accepts up to ten unique criteria with whole weights from 1 to 10', () => {
    expect(criteriaValid(CRITERIA)).toBe(true);
    expect(criteriaValid([])).toBe(true);
    expect(criteriaValid([{ label: 'A', weight: 0 }])).toBe(false);
    expect(criteriaValid([{ label: 'A', weight: 11 }])).toBe(false);
    expect(criteriaValid([{ label: ' ', weight: 1 }])).toBe(false);
    expect(criteriaValid([{ label: 'x'.repeat(41), weight: 1 }])).toBe(false);
    expect(
      criteriaValid([
        { label: 'Fit', weight: 1 },
        { label: 'fit', weight: 2 }
      ])
    ).toBe(false);
    const eleven = Array.from({ length: 11 }, (v, i) => ({ label: `C${i}`, weight: 1 }));
    expect(criteriaValid(eleven)).toBe(false);
  });

  it('builds the matrix from scored reviews only', () => {
    const [line] = matrixRows(
      [
        {
          id: 'a1',
          name: 'Talk',
          weightedAverage: 3.5,
          reviews: [
            { score: 4, weightedScore: 4, criteriaScores: '{"Relevance":5,"Clarity":2}' },
            { score: 3, weightedScore: 3, criteriaScores: '{"Relevance":3,"Clarity":3}' },
            { score: null, reviewer: 'Assigned' }
          ]
        }
      ],
      CRITERIA
    );
    expect(line.cells.map((cell) => cell.text)).toEqual(['4.0', '2.5']);
    expect(line.total).toBe('7.00');
    expect(line.average).toBe('3.50');
    expect(line.reviews).toBe(2);
    expect(scoresOf('not json')).toEqual({});
  });

  it('compares two to four proposals and hides names only while undecided', () => {
    expect(canCompare(['a'])).toBe(false);
    expect(canCompare(['a', 'b'])).toBe(true);
    expect(canCompare(['a', 'b', 'c', 'd', 'e'])).toBe(false);
    const open = {
      status: 'In Review',
      applicant: 'Ana',
      contactId: '003',
      presenters: [{ name: 'Bo' }],
      reviews: [{ reviewer: 'Dana' }]
    };
    const hidden = blinded(open, true, 'Hidden');
    expect(hidden.applicant).toBe('Hidden');
    expect(hidden.contactId).toBeNull();
    expect(hidden.presenters[0].name).toBe('Hidden');
    expect(hidden.reviews[0].reviewer).toBe('Hidden');
    expect(blinded({ ...open, status: 'Accepted' }, true, 'Hidden').applicant).toBe('Ana');
    expect(blinded(open, false, 'Hidden').applicant).toBe('Ana');
  });
});
