import {
  canAddWalkIn,
  codeFrom,
  counts,
  findByCode,
  visibleAttendees,
  walkInRequest
} from 'c/eventCheckInModel';

const JANE = {
  id: 'a09000000000001AAA',
  name: 'Jane Doe',
  email: 'jane@example.org',
  status: 'Registered'
};
const MAX = {
  id: 'a09000000000002AAA',
  name: 'Max Roe',
  ticketName: 'Student',
  status: 'Attended'
};

describe('eventCheckInModel', () => {
  it('reads a record identifier from a scan or typed code', () => {
    expect(codeFrom('  a09000000000001AAA ')).toBe('a09000000000001AAA');
    expect(codeFrom('a09000000000001')).toBe('a09000000000001');
    expect(codeFrom('https://example.org/x')).toBeNull();
    expect(codeFrom('')).toBeNull();
    expect(codeFrom(null)).toBeNull();
  });

  it('finds the attendee a code belongs to, in 15 or 18 characters', () => {
    expect(findByCode([JANE, MAX], 'a09000000000002AAA')).toBe(MAX);
    expect(findByCode([JANE, MAX], 'a09000000000001')).toBe(JANE);
    expect(findByCode([JANE, MAX], 'a09000000000009AAA')).toBeNull();
    expect(findByCode([JANE, MAX], 'not a code')).toBeNull();
    expect(findByCode(undefined, 'a09000000000001AAA')).toBeNull();
  });

  it('searches name, email and ticket, every word, and marks who is in', () => {
    expect(visibleAttendees([JANE, MAX], '')).toHaveLength(2);
    expect(visibleAttendees([JANE, MAX], 'JANE example')).toHaveLength(1);
    expect(visibleAttendees([JANE, MAX], 'student')[0].checkedIn).toBe(true);
    expect(visibleAttendees([JANE, MAX], 'jane student')).toHaveLength(0);
    expect(visibleAttendees(undefined, 'x')).toEqual([]);
  });

  it('counts who is in and who is still to come', () => {
    expect(counts([JANE, MAX])).toEqual({ total: 2, checkedIn: 1, remaining: 1 });
    expect(counts(undefined)).toEqual({ total: 0, checkedIn: 0, remaining: 0 });
  });

  it('needs a last name for a walk-in and shapes the request', () => {
    expect(canAddWalkIn({ firstName: 'Walt' })).toBe(false);
    expect(canAddWalkIn({ lastName: ' Door ' })).toBe(true);
    expect(canAddWalkIn(undefined)).toBe(false);
    expect(
      walkInRequest('e1', { firstName: ' Walt ', lastName: 'Door', ticketTypeId: 't1' })
    ).toEqual({
      eventId: 'e1',
      registrant: { firstName: 'Walt', lastName: 'Door', email: null },
      ticketType: 't1'
    });
    expect(walkInRequest('e1').ticketType).toBeNull();
  });
});
