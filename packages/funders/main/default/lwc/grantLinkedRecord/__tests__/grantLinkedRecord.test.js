import { createElement } from 'lwc';
import GrantLinkedRecord from 'c/grantLinkedRecord';
import getProgram from '@salesforce/apex/GrantProgramController.getProgram';
import setProgram from '@salesforce/apex/GrantProgramController.setProgram';
import getFund from '@salesforce/apex/GrantFundController.getFund';
import setFund from '@salesforce/apex/GrantFundController.setFund';

import { refreshApex } from '@salesforce/apex';

jest.mock(
  '@salesforce/apex/GrantProgramController.getProgram',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantProgramController.setProgram', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/GrantFundController.getFund',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/GrantFundController.setFund', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Program_None', () => ({ default: 'No program' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Fund_None', () => ({ default: 'No fund' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Program_Saved', () => ({ default: 'Program saved' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Shared_Saved', () => ({ default: 'Saved' }), {
  virtual: true
});

const GRANT_ID = 'a01000000000001AAA';

const KINDS = [
  {
    kind: 'Program',
    get: getProgram,
    set: setProgram,
    idKey: 'programId',
    nameKey: 'programName',
    dataId: 'program',
    none: 'No program',
    saved: 'Program saved',
    title: 'c.Core_Shared_Program',
    icon: 'custom:custom88',
    recordId: 'a02000000000001AAA',
    recordName: 'After School',
    card: {}
  },
  {
    kind: 'Fund',
    get: getFund,
    set: setFund,
    idKey: 'fundId',
    nameKey: 'fundName',
    dataId: 'fund',
    none: 'No fund',
    saved: 'Saved',
    title: 'Giving Fund',
    icon: 'custom:custom42',
    recordId: 'a03000000000001AAA',
    recordName: 'Literacy Fund',
    card: { title: 'Giving Fund' }
  }
];

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe.each(KINDS)('c-grant-linked-record ($kind)', (k) => {
  const CARD = {
    available: true,
    canEdit: true,
    [k.idKey]: null,
    [k.nameKey]: null,
    missing: false,
    options: [{ label: k.recordName, value: k.recordId }],
    ...k.card
  };

  function create() {
    const element = createElement('c-grant-linked-record', { is: GrantLinkedRecord });
    element.recordId = GRANT_ID;
    element.kind = k.kind;
    document.body.appendChild(element);
    return element;
  }

  async function render(card = CARD) {
    const element = create();
    k.get.emit(card);
    await flush();
    return element;
  }

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers None and every record, saves the choice and says so', async () => {
    k.set.mockResolvedValue();
    const element = await render();
    const toasts = [];
    element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    expect(one(element, 'lightning-card').title).toBe(k.title);
    expect(one(element, 'lightning-card').iconName).toBe(k.icon);
    const combo = one(element, `[data-id="${k.dataId}"]`);
    expect(combo.options.map((option) => option.label)).toEqual([k.none, k.recordName]);
    expect(one(element, '[data-id="save"]').disabled).toBe(true);

    combo.dispatchEvent(new CustomEvent('change', { detail: { value: k.recordId } }));
    await flush();
    expect(one(element, '[data-id="save"]').disabled).toBe(false);
    one(element, '[data-id="save"]').click();
    await flush();

    expect(k.set).toHaveBeenCalledWith({ grantId: GRANT_ID, [k.idKey]: k.recordId });
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(k.get.getLastConfig()).toEqual({ grantId: GRANT_ID });
    expect(toasts[0]).toEqual(expect.objectContaining({ message: k.saved, variant: 'success' }));
  });

  it('clears the record with None', async () => {
    k.set.mockResolvedValue();
    const element = await render({ ...CARD, [k.idKey]: k.recordId, [k.nameKey]: k.recordName });
    one(element, `[data-id="${k.dataId}"]`).dispatchEvent(
      new CustomEvent('change', { detail: { value: '' } })
    );
    await flush();
    one(element, '[data-id="save"]').click();
    await flush();
    expect(k.set).toHaveBeenCalledWith({ grantId: GRANT_ID, [k.idKey]: null });
  });

  it('draws nothing without the module, and says when the named record has gone', async () => {
    let element = await render({ ...CARD, available: false, canEdit: false, options: [] });
    expect(one(element, '[data-id="card"]')).toBeNull();
    expect(one(element, `[data-id="${k.dataId}"]`)).toBeNull();
    document.body.removeChild(element);

    element = await render({ ...CARD, [k.idKey]: k.recordId, missing: true });
    expect(one(element, '[data-id="missing"]')).not.toBeNull();
  });

  it('shows a reader the record by name, or None', async () => {
    let element = await render({ ...CARD, canEdit: false, [k.nameKey]: k.recordName });
    expect(one(element, '[data-id="read-only"]').textContent.trim()).toBe(k.recordName);
    expect(one(element, `[data-id="${k.dataId}"]`)).toBeNull();
    document.body.removeChild(element);

    element = await render({ ...CARD, canEdit: false });
    expect(one(element, '[data-id="read-only"]').textContent.trim()).toBe(k.none);
  });

  it('shows the reason when the card cannot load or save', async () => {
    const element = create();
    k.get.error({ message: 'No access' });
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent.trim()).toBe('No access');
    document.body.removeChild(element);

    k.set.mockRejectedValue({ body: { message: 'Not allowed' } });
    const saved = await render();
    const toasts = [];
    saved.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    one(saved, `[data-id="${k.dataId}"]`).dispatchEvent(
      new CustomEvent('change', { detail: { value: k.recordId } })
    );
    await flush();
    one(saved, '[data-id="save"]').click();
    await flush();
    expect(toasts[0]).toEqual(
      expect.objectContaining({ message: 'Not allowed', variant: 'error' })
    );
  });
});
