import {
  guestsAt,
  moveSeats,
  overflowAfter,
  partyOf,
  seatingCsv,
  suggestSeating,
  tableCounts,
  unseated
} from 'c/eventSeatingModel';

const TABLES = [
  { id: 't1', name: 'Table 1', capacity: 2, hostName: 'Hal Host' },
  { id: 't2', name: 'Table 2', capacity: 4 },
  { id: 't3', name: 'Acme Table', capacity: 4, sponsorId: 's1', sponsorName: 'Acme, Inc.' }
];
const GUESTS = [
  { id: 'g1', name: 'Ann', partyId: 'p1', tableId: 't1' },
  { id: 'g2', name: 'Bo', partyId: 'p1' },
  { id: 'g3', name: 'Cy', partyId: 'p2', dietary: 'Vegan', access: 'Step "free"' },
  { id: 'g4', name: 'Di', partyId: 'p2' },
  { id: 'g5', name: 'Ed', partyId: 'p2' },
  { id: 'g6', name: 'Flo', partyId: null }
];

describe('eventSeatingModel', () => {
  it('counts seats taken, free and over', () => {
    const rows = tableCounts(TABLES, [
      ...GUESTS,
      { id: 'g7', tableId: 't1' },
      { id: 'g8', tableId: 't1' }
    ]);
    expect(rows[0]).toMatchObject({ seated: 3, free: 0, over: 1, isFull: true, isOver: true });
    expect(rows[1]).toMatchObject({ seated: 0, free: 4, isOver: false });
    expect(tableCounts(undefined, undefined)).toEqual([]);
  });

  it('lists who has no table and who sits at one', () => {
    expect(unseated(GUESTS).map((guest) => guest.id)).toEqual(['g2', 'g3', 'g4', 'g5', 'g6']);
    expect(guestsAt(GUESTS, 't1').map((guest) => guest.id)).toEqual(['g1']);
  });

  it('finds a party as the people on one registration', () => {
    expect(partyOf(GUESTS, 'g4').map((guest) => guest.id)).toEqual(['g4', 'g3', 'g5']);
    expect(partyOf(GUESTS, 'g6')).toHaveLength(1);
    expect(partyOf(GUESTS, 'none')).toEqual([]);
  });

  it('moves a whole party, skipping members already there, or one person', () => {
    expect(moveSeats(GUESTS, 'g2', 't1', true)).toEqual([{ attendeeId: 'g2', tableId: 't1' }]);
    expect(moveSeats(GUESTS, 'g3', 't2', true).map((seat) => seat.attendeeId)).toEqual([
      'g3',
      'g4',
      'g5'
    ]);
    expect(moveSeats(GUESTS, 'g3', 't2', false)).toHaveLength(1);
    expect(moveSeats(GUESTS, 'g1', '', false)).toEqual([{ attendeeId: 'g1', tableId: null }]);
  });

  it('reports only tables a move newly overfills', () => {
    const seats = moveSeats(GUESTS, 'g2', 't1', false);
    expect(overflowAfter(TABLES, GUESTS, seats)).toHaveLength(0);
    const more = [...seats, { attendeeId: 'g6', tableId: 't1' }];
    expect(overflowAfter(TABLES, GUESTS, more).map((row) => row.id)).toEqual(['t1']);
  });

  it('suggests seating by party, skips sponsor tables, and reports who did not fit', () => {
    const plan = suggestSeating(TABLES, GUESTS);
    const at = (id) => plan.seats.find((seat) => seat.attendeeId === id).tableId;
    expect(at('g2')).toBe('t1');
    expect(at('g3')).toBe('t2');
    expect(at('g4')).toBe('t2');
    expect(at('g5')).toBe('t2');
    expect(plan.seats.some((seat) => seat.tableId === 't3')).toBe(false);
    const tight = suggestSeating([{ id: 'a', name: 'A', capacity: 2 }], GUESTS.slice(2));
    expect(tight.unplaced).toEqual(expect.arrayContaining(['g3', 'g4', 'g5']));
  });

  it('writes the seating chart as CSV with quoting', () => {
    const csv = seatingCsv(
      TABLES,
      GUESTS.map((guest) => ({ ...guest, tableId: guest.tableId }))
    );
    const lines = csv.split('\r\n');
    expect(lines[0]).toBe(
      'Table,Table Host,Table Sponsor,Seats,Guest,Organization,Ticket,Dietary Needs,Access Needs'
    );
    expect(lines[1]).toBe('Table 1,Hal Host,,2,Ann,,,,');
    expect(lines).toContain('Table 2,,,4,,,,,');
    expect(lines).toContain(
      '"Acme Table",,"Acme, Inc.",4,,,,,'.replace('"Acme Table"', 'Acme Table')
    );
    expect(lines.some((line) => line.includes('Cy') && line.includes('"Step ""free"""'))).toBe(
      true
    );
  });
});
