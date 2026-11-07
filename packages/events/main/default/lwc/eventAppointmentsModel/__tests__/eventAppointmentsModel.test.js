import {
  MAX_SLOTS,
  generateSlots,
  groupByHost,
  hostClashes,
  nextActions,
  statusWord
} from 'c/eventAppointmentsModel';

const at = (h, m = 0) => new Date(2027, 5, 4, h, m).toISOString();

describe('eventAppointmentsModel', () => {
  it('cuts a day window into back-to-back slots and drops a last slot that runs over', () => {
    const result = generateSlots({
      date: '2027-06-04',
      from: '09:00',
      to: '10:00',
      minutes: 20,
      hostId: 'H1'
    });
    expect(result.slots.map((s) => s.start)).toEqual([at(9), at(9, 20), at(9, 40)]);
    expect(result.slots[2].end).toBe(at(10));
    expect(
      generateSlots({ date: '2027-06-04', from: '09:00', to: '10:00', minutes: 25 }).slots
    ).toHaveLength(2);
  });

  it('leaves out slots that overlap the host own live slots, but not another host or a cancelled one', () => {
    const existing = [
      { hostId: 'H1', start: at(9, 20), end: at(9, 40), status: 'Booked' },
      { hostId: 'H2', start: at(9), end: at(9, 20), status: 'Open' },
      { hostId: 'H1', start: at(9), end: at(9, 20), status: 'Cancelled' }
    ];
    const result = generateSlots({
      date: '2027-06-04',
      from: '09:00',
      to: '10:00',
      minutes: 20,
      existing,
      hostId: 'H1'
    });
    expect(result.skipped).toBe(1);
    expect(result.slots.map((s) => s.start)).toEqual([at(9), at(9, 40)]);
  });

  it('names what is invalid and caps the number of slots', () => {
    expect(generateSlots({ from: '09:00', to: '10:00', minutes: 15 }).invalid).toBe('date');
    expect(
      generateSlots({ date: '2027-06-04', from: '10:00', to: '09:00', minutes: 15 }).invalid
    ).toBe('times');
    expect(generateSlots({ date: '2027-06-04', from: 'x', to: '09:00', minutes: 15 }).invalid).toBe(
      'times'
    );
    expect(
      generateSlots({ date: '2027-06-04', from: '09:00', to: '10:00', minutes: 2 }).invalid
    ).toBe('length');
    const many = generateSlots({ date: '2027-06-04', from: '00:00', to: '23:59', minutes: 5 });
    expect(many.slots).toHaveLength(MAX_SLOTS);
    expect(many.capped).toBe(true);
  });

  it('finds clashing slots of one host and ignores cancelled slots and other hosts', () => {
    const slots = [
      { id: 'a', hostId: 'H1', start: at(9), end: at(10), status: 'Open' },
      { id: 'b', hostId: 'H1', start: at(9, 30), end: at(10, 30), status: 'Booked' },
      { id: 'c', hostId: 'H2', start: at(9), end: at(10), status: 'Open' },
      { id: 'd', hostId: 'H1', start: at(9), end: at(10), status: 'Cancelled' },
      { id: 'e', hostId: 'H1', start: at(10, 30), end: at(11), status: 'Open' }
    ];
    expect([...hostClashes(slots)].sort()).toEqual(['a', 'b']);
  });

  it('groups by host name with counts and time order', () => {
    const groups = groupByHost([
      { id: '1', hostId: 'H2', hostName: 'Zed', start: at(9), end: at(10), status: 'Open' },
      { id: '2', hostId: 'H1', hostName: 'Amy', start: at(11), end: at(12), status: 'Booked' },
      { id: '3', hostId: 'H1', hostName: 'Amy', start: at(9), end: at(10), status: 'Open' }
    ]);
    expect(groups.map((g) => g.hostName)).toEqual(['Amy', 'Zed']);
    expect(groups[0].slots.map((s) => s.id)).toEqual(['3', '2']);
    expect(groups[0].open).toBe(1);
    expect(groups[0].booked).toBe(1);
  });

  it('offers the next actions by status and a badge word', () => {
    expect(nextActions('Open')).toEqual(['book', 'cancel']);
    expect(nextActions('Booked')).toContain('release');
    expect(nextActions('Cancelled')).toEqual(['reopen']);
    expect(nextActions('Other')).toEqual([]);
    expect(statusWord('Booked')).toBe('active');
    expect(statusWord('Other')).toBe('neutral');
  });
});
