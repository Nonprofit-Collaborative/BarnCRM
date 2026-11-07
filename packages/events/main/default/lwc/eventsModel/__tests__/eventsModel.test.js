import { MAX_OCCURRENCES, isMultiDay, seriesStarts, statusWord, whenText } from 'c/eventsModel';

const local = (y, m, d, h = 18, min = 0) => new Date(y, m - 1, d, h, min);

describe('eventsModel', () => {
  describe('seriesStarts', () => {
    it('repeats every week and every two weeks at the same time', () => {
      const weekly = seriesStarts(local(2026, 3, 7), 'weekly', 2);
      expect(weekly).toEqual([local(2026, 3, 14), local(2026, 3, 21)]);
      const biweekly = seriesStarts(local(2026, 3, 7), 'biweekly', 2);
      expect(biweekly).toEqual([local(2026, 3, 21), local(2026, 4, 4)]);
    });

    it('keeps the day of the month, or the last day of a shorter month, without drifting', () => {
      const monthly = seriesStarts(local(2026, 1, 31, 9, 30), 'monthly', 3);
      expect(monthly).toEqual([
        local(2026, 2, 28, 9, 30),
        local(2026, 3, 31, 9, 30),
        local(2026, 4, 30, 9, 30)
      ]);
    });

    it('caps the count and refuses what it cannot read', () => {
      expect(seriesStarts(local(2026, 1, 1), 'weekly', 500)).toHaveLength(MAX_OCCURRENCES);
      expect(seriesStarts(local(2026, 1, 1), 'yearly', 2)).toEqual([]);
      expect(seriesStarts('not a date', 'weekly', 2)).toEqual([]);
      expect(seriesStarts(local(2026, 1, 1), 'weekly', 0)).toEqual([]);
    });
  });

  describe('whenText', () => {
    const options = { locale: 'en-US', timeZone: 'UTC', range: '{0} to {1}' };

    it('names the day once and both times for a one-day event', () => {
      expect(whenText('2026-03-07T18:00:00Z', '2026-03-07T20:00:00Z', options)).toBe(
        'Sat, Mar 7, 2026, 6:00 PM to 8:00 PM'
      );
    });

    it('names both days for a multi-day event', () => {
      expect(whenText('2026-03-07T09:00:00Z', '2026-03-09T17:00:00Z', options)).toBe(
        'Sat, Mar 7, 2026 to Mon, Mar 9, 2026'
      );
      expect(isMultiDay('2026-03-07T09:00:00Z', '2026-03-09T17:00:00Z', 'UTC')).toBe(true);
    });

    it('shows the start alone with no end, and nothing with no start', () => {
      expect(whenText('2026-03-07T18:00:00Z', null, options)).toBe('Sat, Mar 7, 2026, 6:00 PM');
      expect(whenText(null, null, options)).toBe('');
    });
  });

  it('maps each event status to a status word', () => {
    expect(statusWord('Open')).toBe('active');
    expect(statusWord('Draft')).toBe('draft');
    expect(statusWord('Completed')).toBe('completed');
    expect(statusWord('Something Else')).toBe('neutral');
  });
});
