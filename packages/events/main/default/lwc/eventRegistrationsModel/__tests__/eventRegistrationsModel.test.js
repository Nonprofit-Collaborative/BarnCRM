import {
  actionsFor,
  buildRequest,
  canSubmit,
  statusWord,
  summarize
} from 'c/eventRegistrationsModel';

describe('eventRegistrationsModel', () => {
  it('counts attendees by status and the seats left', () => {
    const summary = summarize(
      [
        { status: 'Registered' },
        { status: 'Registered' },
        { status: 'Waitlisted' },
        { status: 'Attended' },
        { status: 'No-Show' },
        { status: 'Cancelled' }
      ],
      5
    );
    expect(summary).toMatchObject({
      registered: 2,
      waitlisted: 1,
      attended: 1,
      noShow: 1,
      cancelled: 1,
      seated: 4,
      seatsLeft: 1
    });
    expect(summarize([], null).seatsLeft).toBeNull();
    expect(summarize([{ status: 'Registered' }, { status: 'Registered' }], 1).seatsLeft).toBe(0);
  });

  it('offers the status changes that fit each status', () => {
    const values = (status, registrationStatus = 'Registered') =>
      actionsFor({ status, registrationStatus }).map((action) => action.value);
    expect(values('Registered')).toEqual([
      'markAttended',
      'markNoShow',
      'cancelAttendee',
      'cancelRegistration'
    ]);
    expect(values('Waitlisted', 'Waitlisted')).toEqual([
      'moveOffWaitlist',
      'cancelAttendee',
      'cancelRegistration'
    ]);
    expect(values('Cancelled', 'Cancelled')).toEqual(['markRegistered']);
    expect(actionsFor({ status: 'No-Show' })[0]).toEqual({
      value: 'markAttended',
      target: 'Attended'
    });
    expect(actionsFor(null)).toEqual([]);
  });

  it('names a badge word per status', () => {
    expect(statusWord('Attended')).toBe('complete');
    expect(statusWord('Waitlisted')).toBe('pending');
    expect(statusWord('Unknown')).toBe('neutral');
  });

  it('builds a request from a chosen or typed person and leaves blank guests out', () => {
    expect(buildRequest('e1', { contactId: 'c1', ticketTypeId: 't1' })).toEqual({
      eventId: 'e1',
      registrant: { contactId: 'c1' },
      ticketType: 't1',
      promoCode: null,
      guests: []
    });
    const typed = buildRequest('e1', {
      firstName: ' Jane ',
      lastName: 'Doe',
      promoCode: ' FRIENDS ',
      guests: [{ firstName: 'Max', lastName: 'Doe', ticketTypeId: 't2' }, { firstName: 'Blank' }]
    });
    expect(typed.registrant).toEqual({
      firstName: 'Jane',
      lastName: 'Doe',
      email: null,
      postalCode: null
    });
    expect(typed.promoCode).toBe('FRIENDS');
    expect(typed.guests).toEqual([
      { person: { firstName: 'Max', lastName: 'Doe', email: null }, ticketTypeId: 't2' }
    ]);
  });

  it('needs a chosen person or a last name to submit', () => {
    expect(canSubmit({ contactId: 'c1' })).toBe(true);
    expect(canSubmit({ lastName: 'Doe' })).toBe(true);
    expect(canSubmit({ firstName: 'Jane' })).toBe(false);
    expect(canSubmit(null)).toBe(false);
  });
});
