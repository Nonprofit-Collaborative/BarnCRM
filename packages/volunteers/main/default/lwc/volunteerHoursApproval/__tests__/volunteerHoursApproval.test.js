import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import VolunteerHoursApproval from 'c/volunteerHoursApproval';
import getHours from '@salesforce/apex/VolunteerHoursApprovalController.getHours';
import approveHours from '@salesforce/apex/VolunteerHoursApprovalController.approve';
import rejectHours from '@salesforce/apex/VolunteerHoursApprovalController.reject';
import reopenHours from '@salesforce/apex/VolunteerHoursApprovalController.reopen';

jest.mock(
  '@salesforce/apex/VolunteerHoursApprovalController.getHours',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/VolunteerHoursApprovalController.approve',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/VolunteerHoursApprovalController.reject',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/VolunteerHoursApprovalController.reopen',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Approve_DoneApprove',
  () => ({ default: 'Entries approved: {0}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Approve_SelectRow',
  () => ({ default: 'Select {0}, {1}, {2} hours' }),
  { virtual: true }
);

const ANA = {
  recordId: 'a05000000000001AAA',
  name: 'VH-000001',
  personName: 'Ana Rivera',
  jobName: 'Food pantry sort',
  shiftName: 'Food pantry sort: 14 Mar 2026',
  dateWorked: '2026-03-14',
  hours: 3,
  status: 'Submitted'
};
const TOM = { ...ANA, recordId: 'a05000000000002AAA', name: 'VH-000002', personName: 'Tom Lee' };

function pageOf(rows, extra) {
  return { canManage: true, rows, hasMore: false, pageSize: 50, ...extra };
}

function build() {
  const element = createElement('c-volunteer-hours-approval', { is: VolunteerHoursApproval });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function tick(element, recordId) {
  const box = element.shadowRoot.querySelector(`.row-select[data-record-id="${recordId}"]`);
  box.checked = true;
  box.dispatchEvent(new CustomEvent('change'));
}

describe('c-volunteer-hours-approval', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the submitted hours in a captioned table with a labelled checkbox per row', async () => {
    getHours.mockResolvedValue(pageOf([ANA, TOM]));
    const element = build();
    await flush();

    expect(getHours).toHaveBeenCalledWith({
      status: 'Submitted',
      jobId: null,
      fromDate: null,
      toDate: null,
      afterDate: null,
      afterId: null
    });
    expect(element.shadowRoot.querySelectorAll('[data-id="row"]').length).toBe(2);
    expect(byId(element, 'caption')).not.toBeNull();
    const boxes = element.shadowRoot.querySelectorAll('.row-select');
    expect(boxes[0].label).toContain('Ana Rivera');
    expect(byId(element, 'approve').disabled).toBe(true);
  });

  it('approves the selected entries, announces the result and reloads', async () => {
    getHours.mockResolvedValue(pageOf([ANA, TOM]));
    approveHours.mockResolvedValue({ moved: 1, refused: [] });
    const toasts = jest.spyOn(Toast, 'show');
    const element = build();
    await flush();

    tick(element, ANA.recordId);
    await flush();
    expect(byId(element, 'approve').disabled).toBe(false);
    byId(element, 'approve').click();
    await flush();

    expect(approveHours).toHaveBeenCalledWith({ hoursIds: [ANA.recordId] });
    expect(toasts).toHaveBeenCalledWith(
      expect.objectContaining({ label: 'Entries approved: 1.', variant: 'success' }),
      expect.anything()
    );
    expect(byId(element, 'result').textContent).toContain('Entries approved: 1.');
    expect(getHours).toHaveBeenCalledTimes(2);
  });

  it('names each entry the server could not move', async () => {
    getHours.mockResolvedValue(pageOf([ANA]));
    approveHours.mockResolvedValue({
      moved: 0,
      refused: [{ recordId: ANA.recordId, message: 'Insufficient access.' }]
    });
    const toasts = jest.spyOn(Toast, 'show');
    const element = build();
    await flush();

    byId(element, 'select-all').checked = true;
    byId(element, 'select-all').dispatchEvent(new CustomEvent('change'));
    await flush();
    byId(element, 'approve').click();
    await flush();

    expect(byId(element, 'refused-list').textContent).toContain('Ana Rivera');
    expect(byId(element, 'refused-list').textContent).toContain('Insufficient access.');
    expect(toasts).toHaveBeenCalledWith(
      expect.objectContaining({ variant: 'warning' }),
      expect.anything()
    );
  });

  it('asks for a reason before rejecting, and sends it', async () => {
    getHours.mockResolvedValue(pageOf([ANA]));
    rejectHours.mockResolvedValue({ moved: 1, refused: [] });
    const element = build();
    await flush();

    tick(element, ANA.recordId);
    await flush();
    byId(element, 'reject').click();
    await flush();

    byId(element, 'confirm-reject').click();
    await flush();
    expect(rejectHours).not.toHaveBeenCalled();

    byId(element, 'reason').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Wrong date' } })
    );
    byId(element, 'confirm-reject').click();
    await flush();

    expect(rejectHours).toHaveBeenCalledWith({ hoursIds: [ANA.recordId], reason: 'Wrong date' });
    expect(byId(element, 'reject-form')).toBeNull();
  });

  it('offers Reopen on the approved list, from the first page again', async () => {
    getHours.mockResolvedValue(pageOf([{ ...ANA, status: 'Approved' }]));
    reopenHours.mockResolvedValue({ moved: 1, refused: [] });
    const element = build();
    await flush();

    byId(element, 'status-filter').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Approved' } })
    );
    await flush();

    expect(getHours).toHaveBeenLastCalledWith(expect.objectContaining({ status: 'Approved' }));
    expect(byId(element, 'approve')).toBeNull();
    tick(element, ANA.recordId);
    await flush();
    byId(element, 'reopen').click();
    await flush();

    expect(reopenHours).toHaveBeenCalledWith({ hoursIds: [ANA.recordId] });
  });

  it('pages forward by the last row and back again', async () => {
    getHours.mockResolvedValue(pageOf([ANA, TOM], { hasMore: true }));
    const element = build();
    await flush();

    expect(byId(element, 'previous').disabled).toBe(true);
    byId(element, 'next').click();
    await flush();

    expect(getHours).toHaveBeenLastCalledWith(
      expect.objectContaining({ afterDate: TOM.dateWorked, afterId: TOM.recordId })
    );
    byId(element, 'previous').click();
    await flush();
    expect(getHours).toHaveBeenLastCalledWith(
      expect.objectContaining({ afterDate: null, afterId: null })
    );
  });

  it('shows a read-only note and no buttons without Manage Volunteers', async () => {
    getHours.mockResolvedValue(pageOf([ANA], { canManage: false }));
    const element = build();
    await flush();

    expect(byId(element, 'read-only')).not.toBeNull();
    expect(byId(element, 'approve')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('.row-select').length).toBe(0);
  });

  it('says so when nothing matches, and shows the message of a refused load', async () => {
    getHours.mockResolvedValueOnce(pageOf([]));
    const element = build();
    await flush();
    expect(byId(element, 'empty-state')).not.toBeNull();

    getHours.mockRejectedValueOnce({ body: { message: 'Not allowed.' } });
    byId(element, 'job-filter').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: 'a01000000000001AAA' } })
    );
    await flush();
    expect(byId(element, 'error-message').textContent.trim()).toBe('Not allowed.');
  });
});
