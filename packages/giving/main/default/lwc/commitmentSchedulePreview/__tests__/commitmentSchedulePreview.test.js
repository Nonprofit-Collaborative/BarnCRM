import { createElement } from 'lwc';
import CommitmentSchedulePreview from 'c/commitmentSchedulePreview';
import getSchedule from '@salesforce/apex/CommitmentController.getSchedule';
import generateNow from '@salesforce/apex/CommitmentController.generateNow';
import changeStatus from '@salesforce/apex/CommitmentController.changeStatus';

jest.mock('@salesforce/apex/CommitmentController.getSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CommitmentController.generateNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CommitmentController.changeStatus', () => ({ default: jest.fn() }), {
  virtual: true
});

const SCHEDULE = {
  saved: true,
  count: 2,
  expectedTotal: 200,
  commitmentStatus: 'Active',
  installments: [
    {
      recordId: 'a01000000000001',
      sequence: 1,
      dueDate: '2026-10-01',
      expectedAmount: 100,
      paidAmount: 100,
      status: 'Paid'
    },
    {
      recordId: 'a01000000000002',
      sequence: 2,
      dueDate: '2026-11-01',
      expectedAmount: 100,
      paidAmount: 0,
      status: 'Overdue'
    }
  ]
};

function build() {
  const element = createElement('c-commitment-schedule-preview', {
    is: CommitmentSchedulePreview
  });
  element.recordId = 'a00000000000001';
  document.body.appendChild(element);
  return element;
}

describe('c-commitment-schedule-preview', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the payments of a commitment', async () => {
    getSchedule.mockResolvedValue(SCHEDULE);
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    const rows = element.shadowRoot.querySelectorAll('tbody tr');
    expect(getSchedule).toHaveBeenCalledWith({ commitmentId: 'a00000000000001' });
    expect(rows.length).toBe(2);
  });

  it('gives each status its own badge', async () => {
    getSchedule.mockResolvedValue(SCHEDULE);
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    const badges = element.shadowRoot.querySelectorAll('lightning-badge');
    expect(badges[0].className).toContain('slds-theme_success');
    expect(badges[1].className).toContain('slds-theme_error');
  });

  it('offers to generate a schedule when there is none', async () => {
    getSchedule.mockResolvedValue({ saved: true, count: 0, installments: [] });
    generateNow.mockResolvedValue(SCHEDULE);
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    const button = element.shadowRoot.querySelector('[data-id="generate"]');
    expect(button).not.toBeNull();

    button.click();
    await Promise.resolve();
    await Promise.resolve();

    expect(generateNow).toHaveBeenCalledWith({ commitmentId: 'a00000000000001' });
    expect(element.shadowRoot.querySelectorAll('tbody tr').length).toBe(2);
  });

  it('offers pause but not resume on an active commitment', async () => {
    getSchedule.mockResolvedValue(SCHEDULE);
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    expect(element.shadowRoot.querySelector('[data-id="pause"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="resume"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="cancel"]')).not.toBeNull();
  });

  it('offers resume but not pause on a paused commitment', async () => {
    getSchedule.mockResolvedValue({ ...SCHEDULE, commitmentStatus: 'Paused' });
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    expect(element.shadowRoot.querySelector('[data-id="resume"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="pause"]')).toBeNull();
  });

  it('offers no status change on a cancelled commitment', async () => {
    getSchedule.mockResolvedValue({ ...SCHEDULE, commitmentStatus: 'Cancelled' });
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    expect(element.shadowRoot.querySelector('[data-id="actions"]')).toBeNull();
  });

  it('pauses a commitment and shows the status it comes back with', async () => {
    getSchedule.mockResolvedValue(SCHEDULE);
    changeStatus.mockResolvedValue({ ...SCHEDULE, commitmentStatus: 'Paused' });
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    element.shadowRoot.querySelector('[data-id="pause"]').click();
    await Promise.resolve();
    await Promise.resolve();

    expect(changeStatus).toHaveBeenCalledWith({
      commitmentId: 'a00000000000001',
      action: 'pause'
    });
    expect(element.shadowRoot.querySelector('[data-id="resume"]')).not.toBeNull();
  });

  it('says so when a status change is refused', async () => {
    getSchedule.mockResolvedValue(SCHEDULE);
    changeStatus.mockRejectedValue({ body: { message: 'That change is not allowed.' } });
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    element.shadowRoot.querySelector('[data-id="cancel"]').click();
    await Promise.resolve();
    await Promise.resolve();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
      'That change is not allowed.'
    );
  });

  it('shows the total expected under the schedule', async () => {
    getSchedule.mockResolvedValue(SCHEDULE);
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    const total = element.shadowRoot.querySelector('[data-id="total"]');
    expect(total).not.toBeNull();
    expect(total.querySelector('lightning-formatted-number').value).toBe(200);
  });

  it('says so when the schedule cannot be read', async () => {
    getSchedule.mockRejectedValue({ body: { message: 'No access to this commitment.' } });
    const element = build();
    await Promise.resolve();
    await Promise.resolve();

    const error = element.shadowRoot.querySelector('[data-id="error"]');
    expect(error.textContent).toBe('No access to this commitment.');
  });
});
