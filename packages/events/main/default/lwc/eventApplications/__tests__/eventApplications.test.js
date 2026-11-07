import { createElement } from 'lwc';
import EventApplications from 'c/eventApplications';
import getApplications from '@salesforce/apex/EventApplicationsController.getApplications';
import saveReview from '@salesforce/apex/EventApplicationsController.saveReview';
import decide from '@salesforce/apex/EventApplicationsController.decide';
import EventRecordModal from 'c/eventRecordModal';

jest.mock(
  '@salesforce/apex/EventApplicationsController.getApplications',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/EventApplicationsController.saveReview',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/EventApplicationsController.decide', () => ({ default: jest.fn() }), {
  virtual: true
});

const EVENT_ID = 'a01000000000001AAA';
const STRONG = 'a07000000000001AAA';
const WEAK = 'a07000000000002AAA';
const DATA = {
  canAdd: true,
  canReview: true,
  canDecide: true,
  fieldLabels: {
    Name: 'Proposal Title',
    Contact__c: 'Applicant',
    Track__c: 'Track',
    Status__c: 'Status',
    Average_Score__c: 'Average Score',
    Score__c: 'Score',
    Notes__c: 'Notes'
  },
  applications: [
    {
      id: STRONG,
      name: 'Scaling Flows',
      contactId: '003000000000001AAA',
      applicant: 'Ana Garcia',
      track: 'Admin',
      status: 'In Review',
      reviewCount: 2,
      averageScore: 4.5,
      myScore: 4,
      myNotes: 'Good',
      reviews: [
        { reviewer: 'Dana', score: 4, notes: 'Good' },
        { reviewer: 'Lee', score: 5, notes: null }
      ]
    },
    {
      id: WEAK,
      name: 'Old Topics',
      applicant: 'Sam Lee',
      status: 'Declined',
      reviewCount: 0,
      noticeResult: 'No email was sent.',
      reviews: []
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getApplications.mockResolvedValue(data);
  const element = createElement('c-event-applications', { is: EventApplications });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const menuOf = (element, index) => all(element, 'lightning-button-menu')[index];
const choose = (menu, value) =>
  menu.dispatchEvent(new CustomEvent('select', { detail: { value } }));
const itemsOf = (menu) => [...menu.querySelectorAll('lightning-menu-item')].map((i) => i.value);

describe('c-event-applications', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists applications with status, average and the reviews', async () => {
    const element = await render();
    expect(getApplications).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="application-row"]')).toHaveLength(2);
    expect(all(element, '[data-id="average"]')[0].textContent).toBe('4.5 (2)');
    const badges = all(element, 'c-barn-status-badge');
    expect(badges[0].status).toBe('review');
    expect(badges[1].status).toBe('rejected');
    expect(all(element, '[data-id="review"]')[0].textContent).toBe('Dana: 4, Good');
    expect(one(element, '[data-id="notice-result"]').textContent).toContain('No email');
  });

  it('offers review, accept and decline only while undecided', async () => {
    const element = await render();
    expect(itemsOf(menuOf(element, 0))).toEqual(['review', 'accept', 'decline', 'edit']);
    expect(itemsOf(menuOf(element, 1))).toEqual(['edit']);
  });

  it('shows the empty state and no add button for a person who cannot add', async () => {
    const element = await render({ ...DATA, canAdd: false, applications: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    expect(one(element, '[data-id="add-application"]')).toBeNull();
  });

  it('saves a score from the review form', async () => {
    const element = await render();
    saveReview.mockResolvedValue();
    choose(menuOf(element, 0), 'review');
    await flush();
    expect(one(element, '[data-id="review-score"]').value).toBe('4');
    one(element, '[data-id="review-score"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '5' } })
    );
    one(element, '[data-id="review-notes"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Great' } })
    );
    await flush();
    one(element, '[data-id="review-save"]').click();
    await flush();
    expect(saveReview).toHaveBeenCalledWith({ applicationId: STRONG, score: 5, notes: 'Great' });
    expect(one(element, '[data-id="review-form-row"]')).toBeNull();
  });

  it('cannot save a review until a score is chosen', async () => {
    const data = {
      ...DATA,
      applications: [{ ...DATA.applications[0], myScore: null, myNotes: null }]
    };
    const element = await render(data);
    choose(menuOf(element, 0), 'review');
    await flush();
    expect(one(element, '[data-id="review-save"]').disabled).toBe(true);
  });

  it('accepts after the person confirms and reloads', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValueOnce(true);
    decide.mockResolvedValue({
      status: 'Accepted',
      speakerId: 'a05000000000001AAA',
      notice: 'Sent'
    });
    choose(menuOf(element, 0), 'accept');
    await flush();
    await flush();
    expect(decide).toHaveBeenCalledWith({
      applicationId: STRONG,
      decision: 'Accepted',
      notify: true
    });
    expect(getApplications).toHaveBeenCalledTimes(2);
  });

  it('does nothing when the confirmation is cancelled', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValueOnce(false);
    choose(menuOf(element, 0), 'decline');
    await flush();
    await flush();
    expect(decide).not.toHaveBeenCalled();
  });

  it('warns when the notice could not go out and shows load errors', async () => {
    const element = await render();
    const toasts = jest.fn();
    element.addEventListener('lightning__showtoast', toasts);
    EventRecordModal.open.mockResolvedValueOnce(true);
    decide.mockResolvedValue({ status: 'Declined', notice: 'NoEmail' });
    choose(menuOf(element, 0), 'decline');
    await flush();
    await flush();
    expect(toasts.mock.calls[0][0].detail.variant).toBe('warning');

    getApplications.mockRejectedValue({ body: { message: 'No access' } });
    const broken = createElement('c-event-applications', { is: EventApplications });
    broken.recordId = EVENT_ID;
    document.body.appendChild(broken);
    await flush();
    expect(one(broken, '[data-id="error-message"]').message).toBe('No access');
  });

  it('opens the add form with the event filled in', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValueOnce({ id: 'a07000000000009AAA' });
    one(element, '[data-id="add-application"]').click();
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        objectApiName: 'Speaker_Application__c',
        defaults: { Event__c: EVENT_ID }
      })
    );
  });
});
