import {
  NO_TRACK,
  UNSCHEDULED,
  clashesOf,
  columnsFor,
  dayOf,
  daysOf,
  overlaps
} from 'c/eventAgendaModel';

const session = (id, start, end, extra = {}) => ({
  id,
  name: id,
  startsAt: start ? `2027-05-0${start}` : null,
  endsAt: end ? `2027-05-0${end}` : null,
  status: 'Confirmed',
  ...extra
});

describe('eventAgendaModel', () => {
  it('works out days, unscheduled last', () => {
    const sessions = [
      session('b', '2T13:00:00Z', '2T14:00:00Z'),
      session('a', '1T09:00:00Z', '1T10:00:00Z'),
      session('c')
    ];
    expect(dayOf(sessions[0], 'UTC')).toBe('2027-05-02');
    expect(dayOf(sessions[2], 'UTC')).toBe(UNSCHEDULED);
    expect(daysOf(sessions, 'UTC')).toEqual(['2027-05-01', '2027-05-02', UNSCHEDULED]);
  });

  it('builds a column per track then No Track, by start time', () => {
    const tracks = [
      { id: 'T1', name: 'Admins' },
      { id: 'T2', name: 'Developers' }
    ];
    const sessions = [
      session('late', '1T15:00:00Z', '1T16:00:00Z', { trackId: 'T1' }),
      session('early', '1T09:00:00Z', '1T10:00:00Z', { trackId: 'T1' }),
      session('keynote', '1T08:00:00Z', '1T09:00:00Z'),
      session('gone', '1T08:00:00Z', '1T09:00:00Z', { trackId: 'deleted' }),
      session('day two', '2T08:00:00Z', '2T09:00:00Z', { trackId: 'T2' })
    ];
    const columns = columnsFor(tracks, sessions, '2027-05-01', 'UTC');
    expect(columns.map((column) => column.id)).toEqual(['T1', 'T2', NO_TRACK]);
    expect(columns[0].sessions.map((s) => s.id)).toEqual(['early', 'late']);
    expect(columns[1].sessions).toHaveLength(0);
    expect(columns[2].sessions.map((s) => s.id)).toEqual(['gone', 'keynote']);
    expect(columnsFor(tracks, sessions, '', 'UTC')[1].sessions).toHaveLength(1);
  });

  it('treats touching times as no overlap', () => {
    expect(
      overlaps(
        session('a', '1T09:00:00Z', '1T10:00:00Z'),
        session('b', '1T10:00:00Z', '1T11:00:00Z')
      )
    ).toBe(false);
    expect(
      overlaps(
        session('a', '1T09:00:00Z', '1T10:30:00Z'),
        session('b', '1T10:00:00Z', '1T11:00:00Z')
      )
    ).toBe(true);
  });

  it('flags room and speaker clashes, ignoring cancelled and unscheduled sessions', () => {
    const sessions = [
      session('a', '1T09:00:00Z', '1T10:00:00Z', { room: 'Hall A', speakerIds: ['S1'] }),
      session('b', '1T09:30:00Z', '1T10:30:00Z', { room: ' hall a ' }),
      session('c', '1T09:45:00Z', '1T10:15:00Z', { room: 'Room 2', speakerIds: ['S1'] }),
      session('d', '1T09:00:00Z', '1T10:00:00Z', { room: 'Hall A', status: 'Cancelled' }),
      session('e', null, null, { room: 'Hall A' })
    ];
    const clashes = clashesOf(sessions);
    expect(clashes.get('a')).toEqual({ room: ['b'], speaker: ['c'] });
    expect(clashes.get('b')).toEqual({ room: ['a'], speaker: [] });
    expect(clashes.get('c')).toEqual({ room: [], speaker: ['a'] });
    expect(clashes.has('d')).toBe(false);
    expect(clashes.has('e')).toBe(false);
  });
});
