/**
 * Seating's shared arithmetic, with no framework in it (EV-13, canonical model 29EV26, plan
 * Section 9.9): how full each table is, who sits where, which people belong to one party (the
 * people on one registration), the moves that keep a party together, a suggested seating for the
 * people not yet seated, and the seating chart as CSV.
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module. A table is
 * { id, name, capacity, hostName, sponsorId, sponsorName }; a guest is
 * { id, name, partyId, tableId, ticketName, organization, dietary, access }.
 */
import { csvCell } from 'c/barnFormat';

/** One table's seats taken, seats left and whether it holds more people than it has seats. */
export function tableCounts(tables, guests) {
  const seated = new Map();
  (guests || []).forEach((guest) => {
    if (guest.tableId) {
      seated.set(guest.tableId, (seated.get(guest.tableId) || 0) + 1);
    }
  });
  return (tables || []).map((table) => {
    const taken = seated.get(table.id) || 0;
    const capacity = Number(table.capacity) || 0;
    return {
      ...table,
      seated: taken,
      free: Math.max(capacity - taken, 0),
      over: Math.max(taken - capacity, 0),
      isFull: taken >= capacity,
      isOver: taken > capacity
    };
  });
}

/** The guests with no table. */
export function unseated(guests) {
  return (guests || []).filter((guest) => !guest.tableId);
}

/** The guests at one table. */
export function guestsAt(guests, tableId) {
  return (guests || []).filter((guest) => guest.tableId === tableId);
}

/** The guest and everyone on the same registration, the guest first. */
export function partyOf(guests, guestId) {
  const list = guests || [];
  const guest = list.find((item) => item.id === guestId);
  if (!guest) {
    return [];
  }
  const mates = guest.partyId
    ? list.filter((item) => item.partyId === guest.partyId && item.id !== guest.id)
    : [];
  return [guest, ...mates];
}

/**
 * The seats to set when one guest is moved to a table (an empty tableId takes the guest off a
 * table). With keepParty the whole party moves, except party members already at the target.
 */
export function moveSeats(guests, guestId, tableId, keepParty) {
  const people = keepParty ? partyOf(guests, guestId) : partyOf(guests, guestId).slice(0, 1);
  return people
    .filter((person) => (person.tableId || '') !== (tableId || ''))
    .map((person) => ({ attendeeId: person.id, tableId: tableId || null }));
}

/** Whether moving these seats would put a table past its capacity, and which table. */
export function overflowAfter(tables, guests, seats) {
  const moved = new Map((seats || []).map((seat) => [seat.attendeeId, seat.tableId]));
  const after = (guests || []).map((guest) => {
    return moved.has(guest.id) ? { ...guest, tableId: moved.get(guest.id) } : guest;
  });
  const counts = tableCounts(tables, after);
  const before = new Map(tableCounts(tables, guests).map((row) => [row.id, row.isOver]));
  return counts.filter((row) => row.isOver && !before.get(row.id));
}

/**
 * A suggested seating for the people with no table: whole parties, largest first, each into the
 * first table with room for the whole party (a party already part-seated joins its table when
 * there is room). Sponsor tables are left for the sponsor's own guests. Returns the seats to set
 * and the people it could not place.
 */
export function suggestSeating(tables, guests) {
  const free = new Map(tableCounts(tables, guests).map((row) => [row.id, row.free]));
  const open = tableCounts(tables, guests).filter((row) => !row.sponsorId);
  const seats = [];
  const left = [];
  const parties = new Map();
  unseated(guests).forEach((guest) => {
    const key = guest.partyId || `single:${guest.id}`;
    parties.set(key, [...(parties.get(key) || []), guest]);
  });
  const ordered = [...parties.values()].sort((a, b) => b.length - a.length);
  ordered.forEach((party) => {
    const home = (guests || []).find(
      (guest) => guest.tableId && party[0].partyId && guest.partyId === party[0].partyId
    );
    const homeTable = home ? open.find((row) => row.id === home.tableId) : undefined;
    const target =
      homeTable && free.get(homeTable.id) >= party.length
        ? homeTable
        : open.find((row) => free.get(row.id) >= party.length);
    if (target) {
      free.set(target.id, free.get(target.id) - party.length);
      party.forEach((guest) => seats.push({ attendeeId: guest.id, tableId: target.id }));
    } else {
      party.forEach((guest) => left.push(guest.id));
    }
  });
  return { seats, unplaced: left };
}

/** The seating chart as CSV text: one row per guest, seated guests by table, then unseated ones. */
export function seatingCsv(tables, guests) {
  const header = [
    'Table',
    'Table Host',
    'Table Sponsor',
    'Seats',
    'Guest',
    'Organization',
    'Ticket',
    'Dietary Needs',
    'Access Needs'
  ];
  const lines = [header];
  const guestRow = (guest, table) => [
    table ? table.name : '',
    table ? table.hostName : '',
    table ? table.sponsorName : '',
    table ? table.capacity : '',
    guest.name,
    guest.organization,
    guest.ticketName,
    guest.dietary,
    guest.access
  ];
  (tables || []).forEach((table) => {
    const seatedHere = guestsAt(guests, table.id);
    if (seatedHere.length) {
      seatedHere.forEach((guest) => lines.push(guestRow(guest, table)));
    } else {
      lines.push([
        table.name,
        table.hostName,
        table.sponsorName,
        table.capacity,
        '',
        '',
        '',
        '',
        ''
      ]);
    }
  });
  unseated(guests).forEach((guest) => lines.push(guestRow(guest, undefined)));
  return lines.map((line) => line.map(csvCell).join(',')).join('\r\n');
}
