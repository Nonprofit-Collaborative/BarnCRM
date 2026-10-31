import { createElement } from 'lwc';
import PersonEnrollments from 'c/personEnrollments';
import getEnrollments from '@salesforce/apex/PersonEnrollmentsController.getEnrollments';
import { canShow, enrollmentRows, lastService } from '../enrollmentRows';

jest.mock(
  '@salesforce/apex/PersonEnrollmentsController.getEnrollments',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Programs_Person_ServicesAttended',
  () => ({ default: '({0} attended in all)' }),
  { virtual: true }
);

const OPEN = {
  recordId: 'a09000000000001AAA',
  programId: 'a08000000000001AAA',
  programName: 'After-School Tutoring',
  stage: 'Enrolled',
  stageLabel: 'Enrolled',
  isOpen: true,
  startDate: '2026-10-01',
  endDate: null
};
const ENDED = {
  recordId: 'a09000000000002AAA',
  programId: 'a08000000000002AAA',
  programName: 'Summer Reading',
  stage: 'Completed',
  stageLabel: 'Completed',
  isOpen: false,
  startDate: '2026-06-01',
  endDate: '2026-08-01'
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount() {
  const element = createElement('c-person-enrollments', { is: PersonEnrollments });
  element.recordId = '003000000000001AAA';
  document.body.appendChild(element);
  return element;
}

const all = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);
const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('enrollmentRows', () => {
  it('keeps the order and marks open and ended rows', () => {
    const rows = enrollmentRows({ enrollments: [OPEN, ENDED] });
    expect(rows.map((row) => row.programLabel)).toEqual([
      'After-School Tutoring',
      'Summer Reading'
    ]);
    expect(rows[0].badgeClass).toContain('slds-theme_success');
    expect(rows[1].badgeClass).toContain('slds-badge_lightest');
    expect(rows[0].endDate).toBe('');
    expect(rows[1].enrollmentHref).toBe('/lightning/r/Enrollment__c/a09000000000002AAA/view');
  });

  it('copes with nothing', () => {
    expect(enrollmentRows(undefined)).toEqual([]);
    expect(canShow(undefined)).toBe(false);
    expect(canShow({ canSee: true })).toBe(true);
  });

  it('gives the last service with its count, or nothing when none', () => {
    expect(
      lastService({ lastServiceDate: '2026-10-20', servicesAttended: 4 }, '({0} attended)')
    ).toEqual({ date: '2026-10-20', attendedText: '(4 attended)' });
    expect(lastService({ servicesAttended: 0 }, '{0}')).toBeNull();
    expect(lastService(undefined, '{0}')).toBeNull();
  });
});

describe('c-person-enrollments', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the enrollments with their stage and dates', async () => {
    getEnrollments.mockResolvedValue({ canSee: true, enrollments: [OPEN, ENDED] });
    const element = mount();
    await flush();

    expect(getEnrollments).toHaveBeenCalledWith({ personId: '003000000000001AAA' });
    expect(all(element, 'enrollment').length).toBe(2);
    expect(one(element, 'program').textContent).toBe('After-School Tutoring');
    expect(all(element, 'ended').length).toBe(1);
    expect(one(element, 'empty')).toBeNull();
    expect(one(element, 'last-service')).toBeNull();
  });

  it('shows the last service and how many were attended', async () => {
    getEnrollments.mockResolvedValue({
      canSee: true,
      enrollments: [OPEN],
      lastServiceDate: '2026-10-20',
      servicesAttended: 3
    });
    const element = mount();
    await flush();

    expect(one(element, 'last-service')).not.toBeNull();
    expect(one(element, 'attended').textContent).toContain('3');
  });

  it('shows no card for a household or a user who cannot see enrollments', async () => {
    getEnrollments.mockResolvedValue({ canSee: false, enrollments: [] });
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('says so when the person has no enrollment', async () => {
    getEnrollments.mockResolvedValue({ canSee: true, enrollments: [] });
    const element = mount();
    await flush();

    expect(one(element, 'empty')).not.toBeNull();
  });

  it('shows a short message when the load fails, and refresh tries again', async () => {
    getEnrollments.mockRejectedValueOnce({ body: { message: 'internal detail' } });
    const element = mount();
    await flush();

    const error = one(element, 'error');
    expect(error).not.toBeNull();
    expect(error.textContent).not.toContain('internal detail');

    getEnrollments.mockResolvedValue({ canSee: true, enrollments: [OPEN], moreThanShown: true });
    one(element, 'refresh').click();
    await flush();

    expect(one(element, 'error')).toBeNull();
    expect(all(element, 'enrollment').length).toBe(1);
    expect(one(element, 'more')).not.toBeNull();
  });
});
