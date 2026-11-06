import {
  PLEDGE,
  RECURRING,
  PERSON,
  ORGANIZATION,
  contextIdFrom,
  isPreviewReady,
  previewFigures,
  toInput
} from 'c/commitmentEntryModel';

const CONTACT_ID = '003000000000001AAA';

function inContext(recordId) {
  const json = JSON.stringify({ type: 'standard__recordPage', attributes: { recordId } });
  return '1.' + btoa(json);
}

describe('commitmentEntryModel', () => {
  it('reads the record New was chosen from', () => {
    expect(contextIdFrom({ inContextOfRef: inContext(CONTACT_ID) })).toBe(CONTACT_ID);
    expect(contextIdFrom({ c__recordId: CONTACT_ID })).toBe(CONTACT_ID);
    expect(contextIdFrom({ inContextOfRef: '1.not base64 json' })).toBeUndefined();
    expect(contextIdFrom({ inContextOfRef: inContext('<script>') })).toBeUndefined();
    expect(contextIdFrom({})).toBeUndefined();
    expect(contextIdFrom(undefined)).toBeUndefined();
  });

  it('previews a pledge once it has a total, a frequency, a first date and an end', () => {
    const pledge = { kind: PLEDGE, total: '1200', frequency: 'Monthly', startDate: '2027-01-15' };
    expect(isPreviewReady(pledge)).toBe(false);
    expect(isPreviewReady({ ...pledge, payments: '12' })).toBe(true);
    expect(isPreviewReady({ ...pledge, lastPaymentDate: '2027-12-15' })).toBe(true);
    expect(isPreviewReady({ ...pledge, total: '0', payments: '12' })).toBe(false);
  });

  it('previews a recurring gift once it has an amount, a frequency and a start date', () => {
    const gift = { kind: RECURRING, amount: '25', frequency: 'Monthly', startDate: '2027-01-15' };
    expect(isPreviewReady(gift)).toBe(true);
    expect(isPreviewReady({ ...gift, amount: '' })).toBe(false);
    expect(isPreviewReady({ ...gift, frequency: undefined })).toBe(false);
  });

  it('sends only the fields of the chosen kind, with the donor in its own field', () => {
    const entry = {
      kind: PLEDGE,
      donorKind: PERSON,
      donorId: CONTACT_ID,
      total: '1200',
      payments: '12',
      lastPaymentDate: '2027-12-15',
      amount: '50',
      frequency: 'Monthly',
      startDate: '2027-01-15'
    };
    const input = toInput(entry, false);
    expect(input.donorContactId).toBe(CONTACT_ID);
    expect(input.donorAccountId).toBeNull();
    expect(input.total).toBe(1200);
    expect(input.payments).toBe(12);
    expect(input.lastPaymentDate).toBeNull();
    expect(input.amount).toBeNull();

    const recurring = toInput({ ...entry, kind: RECURRING, donorKind: ORGANIZATION }, false);
    expect(recurring.donorContactId).toBeNull();
    expect(recurring.donorAccountId).toBe(CONTACT_ID);
    expect(recurring.total).toBeNull();
    expect(recurring.payments).toBeNull();
    expect(recurring.amount).toBe(50);

    expect(toInput(entry, true).donorAccountId).toBe(CONTACT_ID);
    expect(toInput({ ...entry, payments: '' }, false).lastPaymentDate).toBe('2027-12-15');
  });

  it('reads the count, the usual amount and the last payment from a preview', () => {
    expect(previewFigures(null)).toBeNull();
    expect(previewFigures({ installments: [] })).toBeNull();
    expect(
      previewFigures({
        installments: [
          { expectedAmount: 83.33, dueDate: '2027-01-15' },
          { expectedAmount: 83.37, dueDate: '2027-02-15' }
        ]
      })
    ).toEqual({
      count: 2,
      each: 83.33,
      firstDate: '2027-01-15',
      lastAmount: 83.37,
      lastDate: '2027-02-15'
    });
  });
});
