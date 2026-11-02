import { createElement } from 'lwc';
import ServicePlan from 'c/servicePlan';
import getPlan from '@salesforce/apex/ServicePlanController.getPlan';
import getOutcomes from '@salesforce/apex/ServicePlanController.getOutcomes';
import saveGoal from '@salesforce/apex/ServicePlanController.saveGoal';
import saveStep from '@salesforce/apex/ServicePlanController.saveStep';
import markReviewed from '@salesforce/apex/ServicePlanController.markReviewed';
import {
  addMonths,
  formatDate,
  goalCards,
  goalDraft,
  goalPayload,
  isReviewDue,
  newStep,
  outcomeOptions,
  sortGoals,
  stepToggle,
  todayIn
} from '../plan';

jest.mock('@salesforce/apex/ServicePlanController.getPlan', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ServicePlanController.getOutcomes', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ServicePlanController.saveGoal', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ServicePlanController.saveStep', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ServicePlanController.markReviewed', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('lightning/pageReferenceUtils', () => ({ encodeDefaultFieldValues: (v) => v }), {
  virtual: true
});
jest.mock('@salesforce/i18n/timeZone', () => ({ default: 'UTC' }), { virtual: true });
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock(
  '@salesforce/label/c.Core_SetupAssistant_ProgressFormat',
  () => ({ default: '{0} of {1} done' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Programs_Plan_Target', () => ({ default: 'Target {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Plan_WorksToward', () => ({ default: 'Toward {0}' }), {
  virtual: true
});

const ENROLLMENT_ID = 'a09000000000001AAA';
const LABELS = {
  target: 'Target {0}',
  assigned: 'Assigned to {0}',
  nextReviewOn: 'Next review {0}',
  lastReviewedOn: 'Last reviewed {0}',
  closedOn: 'Closed {0}',
  worksToward: 'Toward {0}',
  stepsDone: '{0} of {1} done',
  moreNotes: '{0} notes',
  newStepFor: 'New step for {0}'
};

function goal(overrides) {
  return {
    id: 'a0G000000000001AAA',
    name: 'Find housing',
    status: 'In Progress',
    closed: false,
    targetDate: '2027-03-01',
    nextReviewDate: '2026-10-01',
    steps: [
      { id: 'a0H000000000001AAA', name: 'Apply', status: 'Done' },
      { id: 'a0H000000000002AAA', name: 'Visit', status: 'Not Started' }
    ],
    notes: [
      { id: 'a0C000000000001AAA', noteDate: '2026-10-20', type: 'Check-in', subject: 'Call' }
    ],
    noteCount: 4,
    ...overrides
  };
}

function plan(overrides) {
  return {
    enrollmentId: ENROLLMENT_ID,
    canEdit: true,
    canAddNote: true,
    outcomesAvailable: false,
    goalStatuses: [
      { label: 'Not Started', value: 'Not Started' },
      { label: 'In Progress', value: 'In Progress' },
      { label: 'Achieved', value: 'Achieved' }
    ],
    stepStatuses: [
      { label: 'Not Started', value: 'Not Started' },
      { label: 'Done', value: 'Done' }
    ],
    goals: [goal()],
    ...overrides
  };
}

async function flush() {
  for (let i = 0; i < 10; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function render(returned) {
  getPlan.mockResolvedValue(returned);
  const element = createElement('c-service-plan', { is: ServicePlan });
  element.recordId = ENROLLMENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('plan.js', () => {
  it('works out dates in the user time zone and month arithmetic', () => {
    expect(todayIn('UTC', new Date(Date.UTC(2026, 10, 2, 23, 30)))).toBe('2026-11-02');
    expect(todayIn('Pacific/Auckland', new Date(Date.UTC(2026, 10, 2, 23, 30)))).toBe('2026-11-03');
    expect(addMonths('2026-11-30', 3)).toBe('2027-02-28');
    expect(addMonths('2026-01-31', 1)).toBe('2026-02-28');
    expect(addMonths('2026-11-02', 3)).toBe('2027-02-02');
    expect(formatDate('2027-03-01', 'en-US')).toBe('Mar 1, 2027');
    expect(formatDate(null, 'en-US')).toBe('');
  });

  it('flags open goals past review and sorts open, dated goals first', () => {
    expect(isReviewDue(goal(), '2026-11-02')).toBe(true);
    expect(isReviewDue(goal({ closed: true }), '2026-11-02')).toBe(false);
    expect(isReviewDue(goal({ nextReviewDate: null }), '2026-11-02')).toBe(false);
    const sorted = sortGoals([
      goal({ id: '1', name: 'Closed', closed: true }),
      goal({ id: '2', name: 'Undated', targetDate: null }),
      goal({ id: '3', name: 'Later', targetDate: '2027-06-01' }),
      goal({ id: '4', name: 'Sooner', targetDate: '2027-01-01' })
    ]);
    expect(sorted.map((g) => g.name)).toEqual(['Sooner', 'Later', 'Undated', 'Closed']);
  });

  it('labels each goal card', () => {
    const [card] = goalCards(
      plan({ outcomesAvailable: true, goals: [goal({ outcomeName: 'Housed (Pantry)' })] }),
      '2026-11-02',
      LABELS,
      'en-US'
    );
    expect(card.progress).toBe('1 of 2 done');
    expect(card.facts).toBe('Target Mar 1, 2027');
    expect(card.reviewDue).toBe(true);
    expect(card.outcome).toBe('Toward Housed (Pantry)');
    expect(card.moreNotes).toBe('4 notes');
    expect(card.steps[0].done).toBe(true);
    expect(card.notes[0].line).toBe('Oct 20, 2026 · Check-in · Call');
    expect(goalCards(null, '2026-11-02', LABELS)).toEqual([]);
  });

  it('builds drafts and payloads', () => {
    expect(goalDraft(plan(), 'missing').status).toBe('Not Started');
    expect(goalDraft(plan(), 'a0G000000000001AAA').name).toBe('Find housing');
    const payload = goalPayload({ name: '  Job  ', outcomeId: '' }, ENROLLMENT_ID, true);
    expect(payload).toMatchObject({ name: 'Job', enrollmentId: ENROLLMENT_ID, outcomeId: null });
    expect('outcomeId' in goalPayload({ name: 'Job' }, ENROLLMENT_ID, false)).toBe(false);
    expect(stepToggle('s1', true)).toEqual({ id: 's1', status: 'Done' });
    expect(stepToggle('s1', false)).toEqual({ id: 's1', status: 'Not Started' });
    expect(newStep('g1', '  ')).toBeNull();
    expect(newStep('g1', ' Call ')).toEqual({ goalId: 'g1', name: 'Call' });
    expect(outcomeOptions([{ label: 'A', value: '1' }], 'None')).toEqual([
      { label: 'None', value: '' },
      { label: 'A', value: '1' }
    ]);
  });
});

describe('c-service-plan', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the goals with their steps, notes and review flag', async () => {
    const element = await render(plan());
    expect(getPlan).toHaveBeenCalledWith({ enrollmentId: ENROLLMENT_ID });
    expect(qa(element, 'goal')).toHaveLength(1);
    expect(q(element, 'goal-title').textContent).toBe('Find housing');
    expect(qa(element, 'step')).toHaveLength(2);
    expect(q(element, 'review-due')).not.toBeNull();
    expect(qa(element, 'note')).toHaveLength(1);
    expect(q(element, 'empty')).toBeNull();
  });

  it('says so when there are no goals, and offers nothing to change for a reader', async () => {
    const element = await render(plan({ goals: [], canEdit: false, canAddNote: false }));
    expect(q(element, 'empty')).not.toBeNull();
    expect(q(element, 'add-goal')).toBeNull();
  });

  it('adds a goal through the form', async () => {
    const element = await render(plan({ goals: [] }));
    saveGoal.mockResolvedValue(plan());
    q(element, 'add-goal').click();
    await flush();
    const name = q(element, 'goal-name');
    name.value = 'Find housing';
    name.dispatchEvent(new CustomEvent('change', { detail: { value: 'Find housing' } }));
    await flush();
    q(element, 'save-goal').click();
    await flush();
    const sent = JSON.parse(saveGoal.mock.calls[0][0].goalJson);
    expect(sent).toMatchObject({ enrollmentId: ENROLLMENT_ID, name: 'Find housing' });
    expect('outcomeId' in sent).toBe(false);
    expect(q(element, 'goal-form')).toBeNull();
    expect(qa(element, 'goal')).toHaveLength(1);
  });

  it('offers outcomes where Logic Models is installed', async () => {
    getOutcomes.mockResolvedValue([{ label: 'Housed (Pantry)', value: 'a0X000000000001AAA' }]);
    const element = await render(plan({ outcomesAvailable: true }));
    element.shadowRoot.querySelector('[data-id="edit-goal"]').click();
    await flush();
    expect(getOutcomes).toHaveBeenCalledWith({ enrollmentId: ENROLLMENT_ID });
    expect(q(element, 'goal-outcome').options).toHaveLength(2);
  });

  it('ticks a step done and adds a step', async () => {
    const element = await render(plan());
    saveStep.mockResolvedValue(plan());
    const box = q(element, 'step-done');
    box.checked = false;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(JSON.parse(saveStep.mock.calls[0][0].stepJson)).toEqual({
      id: 'a0H000000000001AAA',
      status: 'Not Started'
    });
    const input = q(element, 'new-step');
    input.value = 'Call landlord';
    input.dispatchEvent(new CustomEvent('change'));
    q(element, 'add-step').click();
    await flush();
    expect(JSON.parse(saveStep.mock.calls[1][0].stepJson)).toEqual({
      goalId: 'a0G000000000001AAA',
      name: 'Call landlord'
    });
  });

  it('marks a goal reviewed with the next review date offered', async () => {
    const element = await render(plan());
    markReviewed.mockResolvedValue(plan());
    q(element, 'mark-reviewed').click();
    await flush();
    const next = q(element, 'review-next');
    expect(next.value).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    q(element, 'save-review').click();
    await flush();
    expect(markReviewed).toHaveBeenCalledWith({
      goalId: 'a0G000000000001AAA',
      nextReviewDate: next.value
    });
    expect(q(element, 'review-form')).toBeNull();
  });

  it('shows a refused save in its own words', async () => {
    const element = await render(plan());
    saveStep.mockRejectedValue({ body: { message: 'No access.' } });
    const box = q(element, 'step-done');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    await flush();
    expect(q(element, 'error-message').textContent.trim()).toBe('No access.');
  });

  it('reports a failed load', async () => {
    getPlan.mockRejectedValue({ body: { message: 'Gone.' } });
    const element = createElement('c-service-plan', { is: ServicePlan });
    element.recordId = ENROLLMENT_ID;
    document.body.appendChild(element);
    await flush();
    await flush();
    expect(q(element, 'error-message').textContent.trim()).toBe('Gone.');
  });
});
