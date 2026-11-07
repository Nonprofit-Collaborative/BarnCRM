import { fillState, fillWord, shiftDefaults, shiftProblem, totals } from 'c/eventVolunteersModel';

const START = '2027-06-04T08:00:00.000Z';
const END = '2027-06-04T18:00:00.000Z';

describe('eventVolunteersModel', () => {
  it('defaults a shift to the first hour of the event, kept inside a short event', () => {
    expect(shiftDefaults(START, END)).toEqual({
      startTime: START,
      endTime: '2027-06-04T09:00:00.000Z',
      needed: 2
    });
    expect(shiftDefaults(START, '2027-06-04T08:30:00.000Z').endTime).toBe(
      '2027-06-04T08:30:00.000Z'
    );
    expect(shiftDefaults(null, null)).toEqual({ startTime: '', endTime: '', needed: 2 });
  });

  it('names what is wrong with a shift', () => {
    const ok = {
      startTime: '2027-06-04T09:00:00.000Z',
      endTime: '2027-06-04T10:00:00.000Z',
      needed: 2
    };
    expect(shiftProblem(ok, START, END)).toBeNull();
    expect(shiftProblem({ ...ok, endTime: ok.startTime }, START, END)).toBe('times');
    expect(shiftProblem({ ...ok, startTime: '' }, START, END)).toBe('times');
    expect(shiftProblem({ ...ok, needed: 0 }, START, END)).toBe('needed');
    expect(shiftProblem({ ...ok, needed: 1.5 }, START, END)).toBe('needed');
    expect(shiftProblem({ ...ok, endTime: '2027-06-04T19:00:00.000Z' }, START, END)).toBe(
      'outside'
    );
    expect(shiftProblem({ ...ok, startTime: '2027-06-04T07:00:00.000Z' }, START, END)).toBe(
      'outside'
    );
  });

  it('grades how full a shift is', () => {
    expect(fillState(0, 3)).toBe('empty');
    expect(fillState(1, 3)).toBe('partial');
    expect(fillState(3, 3)).toBe('full');
    expect(fillState(4, 3)).toBe('full');
    expect(fillWord('full')).toBe('active');
    expect(fillWord('other')).toBe('neutral');
  });

  it('totals jobs, shifts, volunteers wanted and signed up, without counting over-fill', () => {
    const jobs = [
      {
        id: 'a',
        shifts: [
          { needed: 3, filled: 1 },
          { needed: 2, filled: 5 }
        ]
      },
      { id: 'b', shifts: [] }
    ];
    expect(totals(jobs)).toEqual({ jobs: 2, shifts: 2, needed: 5, filled: 3 });
    expect(totals(null)).toEqual({ jobs: 0, shifts: 0, needed: 0, filled: 0 });
  });
});
