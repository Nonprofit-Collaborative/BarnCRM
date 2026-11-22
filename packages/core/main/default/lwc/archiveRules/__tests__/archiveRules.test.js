import { createElement } from 'lwc';
import ArchiveRules from 'c/archiveRules';
import getRules from '@salesforce/apex/ArchiveController.getRules';
import saveRule from '@salesforce/apex/ArchiveController.saveRule';
import previewRule from '@salesforce/apex/ArchiveController.previewRule';
import runRule from '@salesforce/apex/ArchiveController.runRule';

jest.mock('@salesforce/apex/ArchiveController.getRules', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ArchiveController.saveRule', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ArchiveController.previewRule', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ArchiveController.runRule', () => ({ default: jest.fn() }), { virtual: true });

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const PAGE = {
  archivedCount: 950000,
  cap: 1000000,
  warnAt: 900000,
  runLimit: 10000,
  destinations: [
    { key: 'Files', label: 'Files (CSV)', unavailableReason: null },
    { key: 'BigObject', label: 'Big Object', unavailableReason: null },
    { key: 'OffPlatform', label: 'Off Platform', unavailableReason: 'Not set up' }
  ],
  rules: [
    {
      id: 'q1',
      name: 'Old closed lost',
      objectName: 'Contact',
      mine: true,
      destinationLabel: 'Big Object',
      rule: { destination: 'BigObject', frequency: 'weekly', weekday: 7, active: true }
    }
  ],
  candidates: [{ id: 'q2', name: 'Old volunteers', objectName: 'Contact', mine: true }],
  runs: [{ id: 'j1', ruleName: 'Old closed lost', status: 'Complete', running: false, moved: 12, leftOut: 1, log: 'Done' }]
};

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function render(page = PAGE) {
  getRules.mockResolvedValue(page);
  const element = createElement('c-archive-rules', { is: ArchiveRules });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-archive-rules', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists rules, warns near the cap and shows runs', async () => {
    const element = await render();
    expect(one(element, 'rules').textContent).toContain('Old closed lost');
    expect(one(element, 'near-cap')).not.toBeNull();
    expect(one(element, 'usage').value).toBe(95);
    expect(one(element, 'runs').textContent).toContain('Old closed lost');
    expect(one(element, 'choose').options).toEqual([{ label: 'Old volunteers', value: 'q2' }]);
  });

  it('adds a rule with a schedule after typing the current count', async () => {
    previewRule.mockResolvedValue({ count: 7, sample: [], cascades: [] });
    saveRule.mockResolvedValue(PAGE);
    const element = await render();
    const choose = one(element, 'choose');
    choose.dispatchEvent(new CustomEvent('change', { detail: { value: 'q2' } }));
    await flush();
    one(element, 'add-button').click();
    await flush();
    expect(one(element, 'editor')).not.toBeNull();

    one(element, 'destination').dispatchEvent(new CustomEvent('change', { detail: { value: 'OffPlatform' } }));
    await flush();
    expect(one(element, 'destination-reason').textContent).toContain('Not set up');

    one(element, 'destination').dispatchEvent(new CustomEvent('change', { detail: { value: 'BigObject' } }));
    one(element, 'frequency').dispatchEvent(new CustomEvent('change', { detail: { value: 'monthly' } }));
    await flush();
    expect(previewRule).toHaveBeenCalledWith({ queryId: 'q2' });
    one(element, 'month-day').dispatchEvent(new CustomEvent('change', { detail: { value: '3' } }));
    one(element, 'schedule-count').dispatchEvent(new CustomEvent('change', { detail: { value: '7' } }));
    await flush();
    one(element, 'save').click();
    await flush();
    expect(saveRule).toHaveBeenCalledWith({
      queryId: 'q2',
      ruleJson: JSON.stringify({ destination: 'BigObject', frequency: 'monthly', active: true, monthDay: 3 }),
      confirmedCount: 7
    });
    expect(one(element, 'editor')).toBeNull();
  });

  it('previews and runs a rule with the typed count', async () => {
    previewRule.mockResolvedValue({
      count: 12,
      objectLabel: 'Contacts',
      sample: [{ recordId: '003a', name: 'Gala 2019' }],
      cascades: ['Interaction Notes']
    });
    runRule.mockResolvedValue(PAGE);
    const element = await render();
    element.shadowRoot.querySelector('[data-action="preview"]').click();
    await flush();
    expect(one(element, 'sample').textContent).toContain('Gala 2019');
    expect(one(element, 'cascades')).not.toBeNull();
    expect(one(element, 'run').disabled).toBe(true);
    one(element, 'run-count').dispatchEvent(new CustomEvent('change', { detail: { value: '12' } }));
    await flush();
    one(element, 'run').click();
    await flush();
    expect(runRule).toHaveBeenCalledWith({ queryId: 'q1', confirmedCount: 12 });
    expect(one(element, 'notice')).not.toBeNull();
  });

  it('shows a refusal and removes a rule', async () => {
    saveRule.mockRejectedValueOnce({ body: { message: 'Refused' } });
    const element = await render();
    element.shadowRoot.querySelector('[data-action="remove"]').click();
    await flush();
    expect(one(element, 'error').message).toBe('Refused');
    expect(saveRule).toHaveBeenCalledWith({ queryId: 'q1', ruleJson: null, confirmedCount: null });
  });
});
