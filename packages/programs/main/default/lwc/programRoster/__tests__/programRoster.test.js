import { createElement } from 'lwc';
import ProgramRoster from 'c/programRoster';
import getRoster from '@salesforce/apex/ProgramRosterController.getRoster';
import enroll from '@salesforce/apex/ProgramRosterController.enroll';
import setStage from '@salesforce/apex/ProgramRosterController.setStage';
import { format, rosterRows, stageFigures, stageLabel } from '../roster';

jest.mock('@salesforce/apex/ProgramRosterController.getRoster', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProgramRosterController.enroll', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProgramRosterController.setStage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Roster_Changed', () => ({ default: '{0} is now {1}.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Roster_Added', () => ({ default: 'Enrollment added.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Roster_StageFor', () => ({ default: 'Stage for {0}' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Programs_Roster_Caption',
  () => ({ default: 'Enrollments in {0}' }),
  { virtual: true }
);

const PROGRAM_ID = 'a08000000000001AAA';
const PERSON_ID = '003000000000001AAA';
const STAGES = [
  { label: 'Applied', value: 'Applied', count: 1, open: true },
  { label: 'Enrolled', value: 'Enrolled', count: 1, open: true },
  { label: 'Completed', value: 'Completed', count: 3, open: false },
  { label: 'Withdrawn', value: 'Withdrawn', count: 0, open: false }
];
const ANA = {
  recordId: 'a09000000000001AAA',
  name: 'EN-000001',
  personName: 'Ana Rivera',
  stage: 'Enrolled',
  startDate: '2026-10-01',
  endDate: null
};
const HIDDEN = {
  recordId: 'a09000000000002AAA',
  name: 'EN-000002',
  personName: null,
  stage: 'Applied',
  startDate: null,
  endDate: null
};

function rosterOf(enrollments, extra) {
  return {
    programName: 'After-School Tutoring',
    stages: STAGES,
    enrollments,
    showEnded: false,
    moreThanShown: false,
    canAdd: true,
    canEdit: true,
    hasPersonAccounts: false,
    personFilterField: null,
    ...extra
  };
}

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(roster) {
  getRoster.mockResolvedValue(roster);
  const element = createElement('c-program-roster', { is: ProgramRoster });
  element.recordId = PROGRAM_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-program-roster', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the count at each stage and lists the open enrollments', async () => {
    const element = await render(rosterOf([ANA, HIDDEN]));

    expect(getRoster).toHaveBeenCalledWith({ programId: PROGRAM_ID, showEnded: false });
    const figures = [...element.shadowRoot.querySelectorAll('[data-id="figure"]')];
    expect(figures.map((figure) => figure.textContent)).toEqual(['1', '1', '3', '0']);
    const links = [...element.shadowRoot.querySelectorAll('[data-id="enrollment-link"]')];
    expect(links.map((link) => link.textContent)).toEqual(['Ana Rivera', 'EN-000002']);
    expect(one(element, 'caption').textContent).toContain('After-School Tutoring');
    expect(element.shadowRoot.querySelectorAll('.stage-picker')).toHaveLength(2);
  });

  it('says so when there is no one to list', async () => {
    const element = await render(rosterOf([]));

    expect(one(element, 'empty-state')).not.toBeNull();
    expect(one(element, 'caption')).toBeNull();
  });

  it('shows Read Only users the roster without the button or the stage pickers', async () => {
    const element = await render(rosterOf([ANA], { canAdd: false, canEdit: false }));

    expect(one(element, 'enroll-button')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('.stage-picker')).toHaveLength(0);
    expect(element.shadowRoot.querySelector('tbody td').textContent).toBe('Enrolled');
  });

  it('enrolls a person and says so', async () => {
    const element = await render(rosterOf([]));
    enroll.mockResolvedValue(rosterOf([ANA]));

    one(element, 'enroll-button').click();
    await flush();
    expect(one(element, 'save-button').disabled).toBe(true);
    one(element, 'person-picker').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: PERSON_ID } })
    );
    await flush();
    one(element, 'save-button').click();
    await flush();

    expect(enroll).toHaveBeenCalledWith({
      programId: PROGRAM_ID,
      personId: PERSON_ID,
      stage: 'Enrolled',
      showEnded: false
    });
    expect(one(element, 'result-text').textContent).toBe('Enrollment added.');
    expect(one(element, 'enroll-form')).toBeNull();
  });

  it('offers person accounts only in a person account org', async () => {
    const element = await render(
      rosterOf([], { hasPersonAccounts: true, personFilterField: 'Person_Flag' })
    );

    one(element, 'enroll-button').click();
    await flush();

    const picker = one(element, 'person-picker');
    expect(picker.objectApiName).toBe('Account');
    expect(picker.filter.criteria[0].fieldPath).toBe('Person_Flag');
  });

  it('changes a stage in the row and names the person', async () => {
    const element = await render(rosterOf([ANA]));
    setStage.mockResolvedValue(rosterOf([]));

    const picker = element.shadowRoot.querySelector('.stage-picker');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'Completed' } }));
    await flush();

    expect(setStage).toHaveBeenCalledWith({
      enrollmentId: ANA.recordId,
      stage: 'Completed',
      showEnded: false
    });
    expect(one(element, 'result-text').textContent).toBe('Ana Rivera is now Completed.');
  });

  it('shows a refusal in the alert region', async () => {
    const element = await render(rosterOf([ANA]));
    setStage.mockRejectedValue({ body: { message: 'Already open in Tutoring.' } });

    element.shadowRoot
      .querySelector('.stage-picker')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Applied' } }));
    await flush();

    expect(one(element, 'error-message').textContent.trim()).toBe('Already open in Tutoring.');
  });

  it('lists ended enrollments too when Show Ended is on', async () => {
    const element = await render(rosterOf([ANA]));
    getRoster.mockResolvedValue(rosterOf([ANA], { showEnded: true }));

    const toggle = one(element, 'show-ended');
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(getRoster).toHaveBeenLastCalledWith({ programId: PROGRAM_ID, showEnded: true });
  });

  it('says when more are enrolled than it lists', async () => {
    const element = await render(rosterOf([ANA], { moreThanShown: true }));

    expect(one(element, 'more-than-shown')).not.toBeNull();
  });
});

describe('roster display logic', () => {
  it('formats labels and shapes rows without the framework', () => {
    expect(format('{0} is now {1}.', 'Ana', 'Enrolled')).toBe('Ana is now Enrolled.');
    const roster = rosterOf([ANA, HIDDEN]);
    const rows = rosterRows(roster, 'Stage for {0}');
    expect(rows[0].href).toBe(`/lightning/r/Enrollment__c/${ANA.recordId}/view`);
    expect(rows[0].stageFor).toBe('Stage for Ana Rivera');
    expect(rows[1].displayName).toBe('EN-000002');
    expect(rows[1].startDate).toBe('');
    expect(stageFigures(roster).map((figure) => figure.count)).toEqual([1, 1, 3, 0]);
    expect(stageLabel(roster, 'Withdrawn')).toBe('Withdrawn');
    expect(stageLabel(roster, 'Unknown')).toBe('Unknown');
    expect(rosterRows(undefined, 'x')).toEqual([]);
  });
});
