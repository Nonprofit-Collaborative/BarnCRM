import { createElement } from 'lwc';
import EventSponsors from 'c/eventSponsors';
import getSponsors from '@salesforce/apex/EventSponsorsController.getSponsors';
import addSponsor from '@salesforce/apex/EventSponsorsController.addSponsor';
import addDeliverable from '@salesforce/apex/EventSponsorsController.addDeliverable';
import setDeliverableStatus from '@salesforce/apex/EventSponsorsController.setDeliverableStatus';
import removeSponsor from '@salesforce/apex/EventSponsorsController.removeSponsor';
import { deleteRecord } from 'lightning/uiRecordApi';
import EventRecordModal from 'c/eventRecordModal';
import { setHelpTextForTest } from 'c/barnHelpText';

jest.mock('@salesforce/apex/EventSponsorsController.getSponsors', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSponsorsController.addSponsor', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/EventSponsorsController.addDeliverable',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/EventSponsorsController.setDeliverableStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/EventSponsorsController.removeSponsor',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('lightning/uiRecordApi', () => ({ deleteRecord: jest.fn() }), { virtual: true });

const EVENT_ID = 'a01000000000001AAA';
const ACME = 'a08000000000001AAA';
const GOLD = 'a09000000000001AAA';
const LOGO = 'a0A000000000001AAA';
const DATA = {
  canAddSponsor: true,
  canAddLevel: true,
  canEdit: true,
  fieldLabels: {
    Name: 'Sponsor Name',
    Level__c: 'Level',
    Status__c: 'Status',
    Amount__c: 'Amount',
    Deliverables_Total__c: 'Deliverables',
    Levels: 'Sponsorship Levels',
    Deliverable_Name: 'Deliverable',
    Deliverable_Type__c: 'Type',
    Deliverable_Status__c: 'Status'
  },
  deliverableStatuses: [
    { label: 'Pending', value: 'Pending' },
    { label: 'Done', value: 'Done' }
  ],
  deliverableTypes: [
    { label: 'Logo', value: 'Logo' },
    { label: 'Other', value: 'Other' }
  ],
  levels: [{ id: GOLD, name: 'Gold', amount: 5000, benefits: 'Booth', sponsorCount: 1 }],
  sponsors: [
    {
      id: ACME,
      name: 'Acme Software',
      accountId: '001000000000001AAA',
      levelId: GOLD,
      levelName: 'Gold',
      status: 'Committed',
      amount: 5000,
      linkedRecordId: 'a0B000000000001AAA',
      linkedLabel: 'Gift 1042',
      linkedKind: 'Gift',
      deliverables: [
        { id: LOGO, name: 'Logo for the program', type: 'Logo', status: 'Done' },
        { id: 'a0A000000000002AAA', name: 'Booth', type: 'Booth', status: 'Pending', quantity: 1 }
      ]
    },
    {
      id: 'a08000000000002AAA',
      name: 'Beta Org',
      status: 'Prospect',
      amount: 1000,
      deliverables: []
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getSponsors.mockResolvedValue(data);
  const element = createElement('c-event-sponsors', { is: EventSponsors });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const sponsorMenu = (element, index) => all(element, '[data-kind="sponsor"]')[index];
const levelMenu = (element, index) => all(element, '[data-kind="level"]')[index];
const choose = (menu, value) =>
  menu.dispatchEvent(new CustomEvent('select', { detail: { value } }));

describe('c-event-sponsors', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists levels and sponsors with status, progress, total and linked record', async () => {
    setHelpTextForTest({ Events_Sponsors_Totals: 'Committed and confirmed: {0}' });
    const element = await render();
    expect(getSponsors).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="level-row"]')).toHaveLength(1);
    expect(all(element, '[data-id="sponsor-row"]')).toHaveLength(2);
    expect(all(element, '[data-id="progress"]')[0].textContent.trim()).toBe('1/2');
    expect(all(element, '[data-id="progress"]')[1].textContent.trim()).toBe('');
    expect(one(element, '[data-id="linked"]').textContent.trim()).toBe('Gift: Gift 1042');
    expect(all(element, 'c-barn-status-badge')[0].status).toBe('in-progress');
    expect(one(element, '[data-id="totals"]').textContent).toContain('5,000');
    expect(all(element, '[data-id="deliverable"]')).toHaveLength(2);
  });

  it('shows empty states and no controls for a person who cannot add', async () => {
    const element = await render({
      ...DATA,
      canAddSponsor: false,
      canAddLevel: false,
      levels: [],
      sponsors: []
    });
    expect(one(element, '[data-id="levels-empty"]')).not.toBeNull();
    expect(one(element, '[data-id="sponsors-empty"]')).not.toBeNull();
    expect(one(element, '[data-id="add-sponsor"]')).toBeNull();
    expect(one(element, '[data-id="add-level"]')).toBeNull();
  });

  it('adds the picked organization at the chosen level', async () => {
    const element = await render();
    addSponsor.mockResolvedValue('a08000000000009AAA');
    one(element, '[data-id="add-level-choice"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: GOLD } })
    );
    one(element, '[data-id="add-sponsor"]').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '001000000000002AAA' } })
    );
    await flush();
    expect(addSponsor).toHaveBeenCalledWith({
      eventId: EVENT_ID,
      accountId: '001000000000002AAA',
      levelId: GOLD
    });
    expect(getSponsors).toHaveBeenCalledTimes(2);
  });

  it('adds a sponsor with no level when none is chosen', async () => {
    const element = await render();
    addSponsor.mockResolvedValue('a08000000000009AAA');
    one(element, '[data-id="add-sponsor"]').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '001000000000002AAA' } })
    );
    await flush();
    expect(addSponsor).toHaveBeenCalledWith(expect.objectContaining({ levelId: null }));
  });

  it('changes a deliverable status and removes a deliverable', async () => {
    const element = await render();
    setDeliverableStatus.mockResolvedValue();
    deleteRecord.mockResolvedValue();
    const status = one(element, '[data-kind="deliverable-status"]');
    status.dispatchEvent(new CustomEvent('change', { detail: { value: 'Pending' } }));
    await flush();
    expect(setDeliverableStatus).toHaveBeenCalledWith({
      deliverableId: LOGO,
      status: 'Pending'
    });
    one(element, '[data-kind="deliverable-remove"]').click();
    await flush();
    expect(deleteRecord).toHaveBeenCalledWith(LOGO);
  });

  it('adds a deliverable from the sponsor menu once it has a name', async () => {
    const element = await render();
    addDeliverable.mockResolvedValue();
    choose(sponsorMenu(element, 0), 'deliverable');
    await flush();
    expect(one(element, '[data-id="deliverable-save"]').disabled).toBe(true);
    one(element, '[data-id="deliverable-name"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Banner' } })
    );
    one(element, '[data-id="deliverable-type"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Other' } })
    );
    await flush();
    one(element, '[data-id="deliverable-save"]').click();
    await flush();
    expect(addDeliverable).toHaveBeenCalledWith({
      sponsorId: ACME,
      name: 'Banner',
      type: 'Other'
    });
    expect(one(element, '[data-id="deliverable-form-row"]')).toBeNull();
  });

  it('edits a sponsor and a level, and adds a level', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValue({ id: ACME });
    choose(sponsorMenu(element, 0), 'edit');
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ objectApiName: 'Event_Sponsor__c', recordId: ACME })
    );
    choose(levelMenu(element, 0), 'edit');
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ objectApiName: 'Sponsorship_Level__c', recordId: GOLD })
    );
    one(element, '[data-id="add-level"]').click();
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ defaults: { Event__c: EVENT_ID } })
    );
  });

  it('removes a sponsor and a level after the person confirms', async () => {
    const element = await render();
    removeSponsor.mockResolvedValue();
    deleteRecord.mockResolvedValue();
    EventRecordModal.open.mockResolvedValueOnce(true);
    choose(sponsorMenu(element, 0), 'remove');
    await flush();
    await flush();
    expect(removeSponsor).toHaveBeenCalledWith({ sponsorId: ACME });
    EventRecordModal.open.mockResolvedValueOnce(true);
    choose(levelMenu(element, 0), 'remove');
    await flush();
    await flush();
    expect(deleteRecord).toHaveBeenCalledWith(GOLD);
  });

  it('shows a refusal in a toast and the load error', async () => {
    const element = await render();
    removeSponsor.mockRejectedValue({ body: { message: 'Not yours' } });
    const toasts = jest.fn();
    element.addEventListener('lightning__showtoast', toasts);
    EventRecordModal.open.mockResolvedValueOnce(true);
    choose(sponsorMenu(element, 0), 'remove');
    await flush();
    await flush();
    expect(toasts).toHaveBeenCalled();

    getSponsors.mockRejectedValue({ body: { message: 'No access' } });
    const broken = createElement('c-event-sponsors', { is: EventSponsors });
    broken.recordId = EVENT_ID;
    document.body.appendChild(broken);
    await flush();
    expect(one(broken, '[data-id="error-message"]').message).toBe('No access');
  });
});
