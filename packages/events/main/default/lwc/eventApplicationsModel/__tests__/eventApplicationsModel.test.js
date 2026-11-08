import {
  averageText,
  isUndecided,
  isValidScore,
  scoreOptions,
  statusWord
} from 'c/eventApplicationsModel';

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
});
