import { createElement } from 'lwc';
import GrantOutcomes from 'c/grantOutcomes';
import getOutcomes from '@salesforce/apex/GrantOutcomeController.getOutcomes';
import setOutcome from '@salesforce/apex/GrantOutcomeController.setOutcome';

jest.mock('@salesforce/apex/GrantOutcomeController.getOutcomes', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantOutcomeController.setOutcome', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Shared_NoOutcome', () => ({ default: 'No outcome' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Funders_Outcomes_PeriodLine',
  () => ({ default: '{0}: target {1}, result {2}' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Funders_Outcomes_NotSet', () => ({ default: 'not set' }), {
  virtual: true
});

const OUTCOME = {
  id: 'o1',
  name: 'Students read at home',
  model: 'Reading',
  type: 'Outcome',
  indicators: [
    {
      id: 'i1',
      name: 'Students reading daily',
      unit: 'students',
      periods: [{ name: '2026', target: 30, result: null }]
    }
  ]
};

const CARD = {
  available: true,
  canEdit: true,
  options: [{ label: 'Reading: Students read at home', value: 'o1' }],
  rows: [
    {
      requirementId: 'r1',
      name: 'Final report',
      type: 'Narrative Report',
      outcomeId: 'o1',
      outcome: OUTCOME,
      missing: false
    },
    {
      requirementId: 'r2',
      name: 'Site visit',
      type: 'Site Visit',
      outcomeId: 'gone',
      outcome: null,
      missing: true
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(card = CARD) {
  getOutcomes.mockResolvedValue(card);
  const element = createElement('c-grant-outcomes', { is: GrantOutcomes });
  element.recordId = 'g1';
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-grant-outcomes', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows each requirement, the linked outcome results and a missing outcome', async () => {
    const element = await render();
    expect(all(element, '[data-id="requirement"]')).toHaveLength(2);
    const indicator = one(element, '[data-id="indicator"]').textContent;
    expect(indicator).toContain('Students reading daily (students)');
    expect(indicator).toContain('2026: target 30, result not set');
    expect(all(element, '[data-id="missing"]')).toHaveLength(1);
    const combo = one(element, 'lightning-combobox');
    expect(combo.options.map((option) => option.label)).toEqual([
      'No outcome',
      'Reading: Students read at home'
    ]);
  });

  it('saves a new choice', async () => {
    setOutcome.mockResolvedValue();
    const element = await render();
    const combo = one(element, 'lightning-combobox');
    combo.dispatchEvent(new CustomEvent('change', { detail: { value: '' } }));
    await flush();
    const save = one(element, 'lightning-button');
    expect(save.disabled).toBe(false);
    save.click();
    await flush();
    expect(setOutcome).toHaveBeenCalledWith({ requirementId: 'r1', outcomeId: null });
    expect(getOutcomes).toHaveBeenCalledTimes(2);
  });

  it('shows the outcome read-only to someone who cannot edit', async () => {
    const element = await render({ ...CARD, canEdit: false });
    expect(one(element, 'lightning-combobox')).toBeNull();
    expect(one(element, '[data-id="read-only"]').textContent).toBe(
      'Reading: Students read at home'
    );
  });

  it('says when Logic Models is not installed or there are no requirements', async () => {
    let element = await render({ available: false, canEdit: false, options: [], rows: [] });
    expect(one(element, '[data-id="not-installed"]')).not.toBeNull();
    document.body.removeChild(element);
    element = await render({ available: true, canEdit: true, options: [], rows: [] });
    expect(one(element, '[data-id="no-requirements"]')).not.toBeNull();
  });

  it('shows a load error', async () => {
    getOutcomes.mockRejectedValue({ body: { message: 'Broken' } });
    const element = createElement('c-grant-outcomes', { is: GrantOutcomes });
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent).toBe('Broken');
  });
});
