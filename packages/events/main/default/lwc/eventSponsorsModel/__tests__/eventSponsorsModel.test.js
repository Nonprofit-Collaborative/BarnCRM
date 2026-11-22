import {
  committedTotal,
  deliverableFields,
  linkedText,
  progressText,
  sponsorWord
} from 'c/eventSponsorsModel';

const NAMES = { sponsor: 'Event_Sponsor__c', name: 'Name', type: 'Type__c' };

describe('eventSponsorsModel', () => {
  it('builds a checklist item trimmed, Type Other by default, none without a name', () => {
    expect(deliverableFields('s1', '  Banner ', '', NAMES)).toEqual({
      Event_Sponsor__c: 's1',
      Name: 'Banner',
      Type__c: 'Other'
    });
    expect(deliverableFields('s1', 'x'.repeat(90), 'Logo', NAMES).Name).toHaveLength(80);
    expect(deliverableFields('s1', 'Logo', 'Logo', NAMES).Type__c).toBe('Logo');
    expect(deliverableFields('s1', '   ', 'Logo', NAMES)).toBeNull();
    // The caller's names key the result, whatever the org calls the fields.
    expect(
      deliverableFields('s1', 'Logo', 'Logo', {
        sponsor: 'Owner__c',
        name: 'Name',
        type: 'Kind__c'
      })
    ).toEqual({ Owner__c: 's1', Name: 'Logo', Kind__c: 'Logo' });
  });

  it('gives each status a badge word and an unknown one a neutral look', () => {
    expect(sponsorWord('Confirmed')).toBe('approved');
    expect(sponsorWord('Declined')).toBe('rejected');
    expect(sponsorWord('Mystery')).toBe('neutral');
  });

  it('reports checklist progress as done over total, empty with no items', () => {
    const items = [{ status: 'Done' }, { status: 'Pending' }, { status: 'Done' }];
    expect(progressText(items)).toBe('2/3');
    expect(progressText([])).toBe('');
    expect(progressText(undefined)).toBe('');
  });

  it('adds only committed and confirmed amounts, treating blanks as zero', () => {
    const sponsors = [
      { status: 'Committed', amount: 5000 },
      { status: 'Confirmed', amount: 2500.5 },
      { status: 'Prospect', amount: 9999 },
      { status: 'Declined', amount: 100 },
      { status: 'Confirmed', amount: null }
    ];
    expect(committedTotal(sponsors)).toBe(7500.5);
    expect(committedTotal(undefined)).toBe(0);
  });

  it('names a linked record only when it could be read', () => {
    expect(linkedText({ linkedLabel: 'Gift 1042', linkedKind: 'Gift' })).toBe('Gift: Gift 1042');
    expect(linkedText({ linkedLabel: 'Award' })).toBe('Award');
    expect(linkedText({ linkedRecordId: 'a0X000000000001AAA' })).toBe('');
    expect(linkedText(null)).toBe('');
  });
});
