import { createElement } from 'lwc';
import EventApplications from 'c/eventApplications';
import getApplications from '@salesforce/apex/EventApplicationsController.getApplications';
import saveReview from '@salesforce/apex/EventApplicationsController.saveReview';
import decide from '@salesforce/apex/EventApplicationsController.decide';
import EventRecordModal from 'c/eventRecordModal';
import saveCriteria from '@salesforce/apex/EventProposalReview.saveCriteria';
import addPresenter from '@salesforce/apex/EventProposalReview.addPresenter';
import assignReviewers from '@salesforce/apex/EventProposalReview.assignReviewers';

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
jest.mock('@salesforce/apex/EventProposalReview.saveCriteria', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventProposalReview.addPresenter', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventProposalReview.removePresenter', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventProposalReview.assignReviewers', () => ({ default: jest.fn() }), {
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
    expect(itemsOf(menuOf(element, 0))).toEqual([
      'review',
      'presenter',
      'accept',
      'decline',
      'edit'
    ]);
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
    expect(saveReview).toHaveBeenCalledWith({
      applicationId: STRONG,
      score: 5,
      notes: 'Great',
      criteriaScoresJson: null
    });
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

  it('scores each weighted criterion and saves the rounded score with the criteria scores', async () => {
    const criteria = [
      { label: 'Relevance', weight: 2 },
      { label: 'Clarity', weight: 1 }
    ];
    const element = await render({ ...DATA, criteria });
    saveReview.mockResolvedValue();
    choose(menuOf(element, 0), 'review');
    await flush();
    const pickers = all(element, '[data-id="criterion-score"]');
    expect(pickers).toHaveLength(2);
    expect(one(element, '[data-id="review-save"]').disabled).toBe(true);
    pickers[0].dispatchEvent(new CustomEvent('change', { detail: { value: '5' } }));
    pickers[1].dispatchEvent(new CustomEvent('change', { detail: { value: '2' } }));
    await flush();
    // The help catalog is not loaded under Jest, so the sentence reads as its key.
    expect(one(element, '[data-id="weighted"]').textContent).toBe(
      'c.Events_Applications_WeightedScore'
    );
    expect(one(element, '[data-id="review-save"]').disabled).toBe(false);
    one(element, '[data-id="review-save"]').click();
    await flush();
    expect(saveReview).toHaveBeenCalledWith({
      applicationId: STRONG,
      score: 4,
      notes: 'Good',
      criteriaScoresJson: JSON.stringify({ Relevance: 5, Clarity: 2 })
    });
  });

  it('hides names under blind review until decided, and filters to my assignments', async () => {
    const data = {
      ...DATA,
      blindReview: true,
      applications: [
        { ...DATA.applications[0], assignedToMe: true, presenters: [] },
        DATA.applications[1]
      ]
    };
    const element = await render(data);
    const names = all(element, '[data-id="application-row"] td:nth-child(3)').map((cell) =>
      cell.textContent.trim()
    );
    expect(names[0]).toBe('c.Events_Applications_Hidden');
    expect(names[1]).toBe('Sam Lee');
    expect(one(element, '[data-id="assigned"]')).not.toBeNull();
    const mine = one(element, '[data-id="mine"]');
    mine.checked = true;
    mine.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(all(element, '[data-id="application-row"]')).toHaveLength(1);
  });

  it('saves review criteria, assigns a reviewer to the selected and adds a presenter', async () => {
    const element = await render({ ...DATA, canEditEvent: true, canAssign: true });
    saveCriteria.mockResolvedValue();
    one(element, '[data-id="criteria-toggle"]').click();
    await flush();
    one(element, '[data-id="add-criterion"]').click();
    await flush();
    const inputs = all(element, '[data-id="criterion"] lightning-input');
    inputs[0].dispatchEvent(new CustomEvent('change', { detail: { value: 'Relevance' } }));
    inputs[1].dispatchEvent(new CustomEvent('change', { detail: { value: '3' } }));
    await flush();
    one(element, '[data-id="criteria-save"]').click();
    await flush();
    expect(saveCriteria).toHaveBeenCalledWith({
      eventId: EVENT_ID,
      criteriaJson: JSON.stringify([{ label: 'Relevance', weight: 3 }])
    });

    assignReviewers.mockResolvedValue(1);
    const box = all(element, '[data-id="select"]')[0];
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    one(element, '[data-id="assign-toggle"]').click();
    await flush();
    one(element, '[data-id="reviewer"]').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '005000000000001AAA' } })
    );
    one(element, '[data-id="assign"]').click();
    await flush();
    expect(assignReviewers).toHaveBeenCalledWith({
      applicationIds: [STRONG],
      reviewerId: '005000000000001AAA'
    });

    addPresenter.mockResolvedValue('a0P000000000001AAA');
    choose(menuOf(element, 0), 'presenter');
    await flush();
    one(element, '[data-id="presenter-person"]').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '003000000000002AAA' } })
    );
    await flush();
    one(element, '[data-id="presenter-save"]').click();
    await flush();
    expect(addPresenter).toHaveBeenCalledWith({
      applicationId: STRONG,
      contactId: '003000000000002AAA',
      role: 'Speaker'
    });
  });

  it('compares two selected proposals side by side and shows the matrix', async () => {
    const element = await render({ ...DATA, criteria: [{ label: 'Relevance', weight: 1 }] });
    one(element, '[data-id="compare"]').click();
    await flush();
    expect(one(element, '[data-id="compare-panel"]')).toBeNull();
    all(element, '[data-id="select"]').forEach((box) => {
      box.checked = true;
      box.dispatchEvent(new CustomEvent('change'));
    });
    one(element, '[data-id="compare"]').click();
    one(element, '[data-id="matrix-toggle"]').click();
    await flush();
    expect(all(element, '[data-id="compared"]')).toHaveLength(2);
    expect(all(element, '[data-id="matrix-row"]')).toHaveLength(2);
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
