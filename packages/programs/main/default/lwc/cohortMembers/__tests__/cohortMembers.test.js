import { createElement } from 'lwc';
import CohortMembers from 'c/cohortMembers';
import getMembers from '@salesforce/apex/CohortController.getMembers';
import addMembers from '@salesforce/apex/CohortController.addMembers';
import removeMember from '@salesforce/apex/CohortController.removeMember';
import getPersonName from '@salesforce/apex/CohortController.getPersonName';
import {
  addPayload,
  addedMessage,
  allTicked,
  candidateRows,
  chosenCount,
  format,
  memberRows,
  withPerson,
  withTicked,
  withoutPerson
} from '../members';

jest.mock('@salesforce/apex/CohortController.getMembers', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CohortController.addMembers', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CohortController.removeMember', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CohortController.getPersonName', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Cohort_AddedMany', () => ({ default: '{0} added.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Cohort_SomeFailed', () => ({ default: '{0} not.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Cohort_Chosen', () => ({ default: 'Chosen: {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Cohort_MemberCount', () => ({ default: 'Members ({0})' }), {
  virtual: true
});

const COHORT_ID = 'a0C000000000001AAA';
const ANA = { enrollmentId: 'a09000000000001AAA', personName: 'Ana Rivera', stage: 'Enrolled' };
const BEN = { enrollmentId: 'a09000000000002AAA', personName: 'Ben Okafor', stage: 'Applied' };
const CARA = { enrollmentId: 'a09000000000003AAA', personName: 'Cara Diaz', stage: 'Enrolled' };

function membersOf(extra) {
  return {
    cohortId: COHORT_ID,
    cohortName: 'Spring',
    programId: 'a08000000000001AAA',
    programName: 'Job Readiness',
    members: [ANA],
    candidates: [BEN, CARA],
    moreThanShown: false,
    canEdit: true,
    canEnroll: true,
    hasPersonAccounts: false,
    personFilterField: null,
    maxPerAction: 200,
    added: 0,
    failures: [],
    ...extra
  };
}

async function flush() {
  for (let i = 0; i < 10; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function render() {
  const element = createElement('c-cohort-members', { is: CohortMembers });
  element.recordId = COHORT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('members (framework free)', () => {
  it('keeps the picked people once each and the ticks', () => {
    let picked = withPerson([], { id: '003A', name: 'Dee' });
    picked = withPerson(picked, { id: '003A', name: 'Dee' });
    picked = withPerson(picked, { id: '003B' });
    expect(picked).toEqual([
      { id: '003A', name: 'Dee' },
      { id: '003B', name: '003B' }
    ]);
    expect(withPerson(picked, null)).toBe(picked);
    expect(withoutPerson(picked, '003A')).toEqual([{ id: '003B', name: '003B' }]);
    let ticked = withTicked([], 'e1', true);
    ticked = withTicked(ticked, 'e2', true);
    expect(withTicked(ticked, 'e1', false)).toEqual(['e2']);
    expect(allTicked([BEN, CARA], [])).toEqual([BEN.enrollmentId, CARA.enrollmentId]);
    expect(allTicked([BEN, CARA], [BEN.enrollmentId, CARA.enrollmentId])).toEqual([]);
    expect(allTicked([], [])).toEqual([]);
  });

  it('sends only ticks still offered, and words the result', () => {
    const picked = [{ id: '003A', name: 'Dee' }];
    expect(addPayload([BEN], [BEN.enrollmentId, 'gone'], picked)).toEqual({
      enrollmentIds: [BEN.enrollmentId],
      personIds: ['003A']
    });
    expect(chosenCount([BEN], [BEN.enrollmentId], picked)).toBe(2);
    const labels = { addedOne: 'One added.', addedMany: '{0} added.', someFailed: '{0} not.' };
    expect(addedMessage({ added: 1, failures: [] }, labels)).toBe('One added.');
    expect(addedMessage({ added: 2, failures: [{}] }, labels)).toBe('2 added. 1 not.');
    expect(addedMessage(undefined, labels)).toBe('0 added.');
    expect(candidateRows([BEN], [BEN.enrollmentId], { tickFor: 'Add {0}' })[0]).toMatchObject({
      checked: true,
      tickLabel: 'Add Ben Okafor'
    });
    expect(memberRows([ANA], { removeFor: 'Remove {0}' })[0].removeLabel).toBe('Remove Ana Rivera');
    expect(memberRows(undefined, { removeFor: '' })).toEqual([]);
    expect(format('{0} and {1}', 'a')).toBe('a and {1}');
  });
});

describe('c-cohort-members', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the members and who may be added', async () => {
    getMembers.mockResolvedValue(membersOf());
    const element = await render();
    expect(getMembers).toHaveBeenCalledWith({ cohortId: COHORT_ID });
    expect(q(element, 'member-count').textContent).toBe('Members (1)');
    expect(qa(element, 'member')).toHaveLength(1);
    expect(qa(element, 'candidate')).toHaveLength(2);
    expect(q(element, 'add').disabled).toBe(true);
  });

  it('adds ticked enrollments and picked people, and lists who failed', async () => {
    getMembers.mockResolvedValue(membersOf());
    getPersonName.mockResolvedValue('Dee Park');
    addMembers.mockResolvedValue(
      membersOf({
        members: [ANA, BEN],
        candidates: [CARA],
        added: 2,
        failures: [{ personName: 'Dee Park', message: 'Already enrolled.' }]
      })
    );
    const element = await render();
    q(element, 'select-all').click();
    await flush();
    const ticks = qa(element, 'tick');
    ticks[1].checked = false;
    ticks[1].dispatchEvent(new CustomEvent('change'));
    q(element, 'person-picker').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '003000000000009AAA' } })
    );
    await flush();
    q(element, 'add-to-list').click();
    await flush();
    expect(qa(element, 'picked')).toHaveLength(1);
    expect(q(element, 'chosen').textContent).toBe('Chosen: 2');

    q(element, 'add').click();
    await flush();
    expect(addMembers).toHaveBeenCalledWith({
      cohortId: COHORT_ID,
      enrollmentIds: [BEN.enrollmentId],
      personIds: ['003000000000009AAA']
    });
    expect(q(element, 'result').textContent).toBe('2 added. 1 not.');
    expect(qa(element, 'failure')).toHaveLength(1);
    expect(q(element, 'failure').textContent).toContain('Already enrolled.');
    expect(qa(element, 'picked')).toHaveLength(0);
  });

  it('takes a picked person off the list, and removes a member', async () => {
    getMembers.mockResolvedValue(membersOf());
    getPersonName.mockRejectedValue({});
    removeMember.mockResolvedValue(membersOf({ members: [] }));
    const element = await render();
    q(element, 'person-picker').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '003000000000009AAA' } })
    );
    await flush();
    q(element, 'add-to-list').click();
    await flush();
    expect(q(element, 'picked').label).toBe('003000000000009AAA');
    q(element, 'picked').dispatchEvent(new CustomEvent('remove'));
    await flush();
    expect(qa(element, 'picked')).toHaveLength(0);

    q(element, 'remove').click();
    await flush();
    expect(removeMember).toHaveBeenCalledWith({
      cohortId: COHORT_ID,
      enrollmentId: ANA.enrollmentId
    });
    expect(q(element, 'members-empty')).not.toBeNull();
  });

  it('is read only without edit access and reports failures', async () => {
    getMembers.mockResolvedValue(membersOf({ canEdit: false, canEnroll: false }));
    const element = await render();
    expect(q(element, 'add-people')).toBeNull();
    expect(q(element, 'remove')).toBeNull();

    getMembers.mockRejectedValue({ body: { message: 'Not found.' } });
    const second = await render();
    expect(q(second, 'error-message').textContent).toContain('Not found.');
  });

  it('shows a refused add in its own words', async () => {
    getMembers.mockResolvedValue(membersOf({ candidates: [] }));
    addMembers.mockRejectedValue({});
    getPersonName.mockResolvedValue('Dee Park');
    const element = await render();
    expect(q(element, 'no-candidates')).not.toBeNull();
    q(element, 'person-picker').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '003000000000009AAA' } })
    );
    await flush();
    q(element, 'add-to-list').click();
    await flush();
    q(element, 'add').click();
    await flush();
    expect(q(element, 'error-message').textContent).toContain('Programs_Cohort_ActionFailed');
  });
});
