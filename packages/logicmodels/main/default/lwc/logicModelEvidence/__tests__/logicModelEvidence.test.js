import { createElement } from 'lwc';
import LogicModelEvidence from 'c/logicModelEvidence';
import saveEvidence from '@salesforce/apex/LogicModelBuilderController.saveEvidence';
import remove from '@salesforce/apex/LogicModelBuilderController.remove';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock(
  '@salesforce/apex/LogicModelBuilderController.saveEvidence',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/LogicModelBuilderController.remove', () => ({ default: jest.fn() }), {
  virtual: true
});

const MODEL = Object.freeze({
  id: 'm1',
  evidenceText: {
    title: 'Assumption Evidence',
    summary: 'What It Shows',
    source: 'Source',
    sourceUrl: 'Source Link',
    date: 'Date',
    strength: 'Strength',
    strengths: [
      { value: 'Strong', label: 'Strong' },
      { value: 'Moderate', label: 'Moderate' },
      { value: 'Limited', label: 'Limited' },
      { value: 'Challenges', label: 'Challenges' }
    ]
  },
  links: [
    {
      id: 'l1',
      fromId: 'a1',
      toId: 'o1',
      assumption: 'Kids come.',
      evidence: [
        {
          id: 'e1',
          summary: 'Attendance doubled.',
          source: 'Program records',
          sourceUrl: 'https://example.org',
          date: '2025-06-30',
          strength: 'Strong'
        }
      ]
    },
    { id: 'l2', fromId: 'a1', toId: 'c1', assumption: '', evidence: [] }
  ]
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const q = (element, selector) => element.shadowRoot.querySelector(selector);
const qa = (element, selector) => element.shadowRoot.querySelectorAll(selector);

async function render(linkId = 'l1', canEdit = true) {
  const element = createElement('c-logic-model-evidence', { is: LogicModelEvidence });
  element.model = MODEL;
  element.linkId = linkId;
  element.canEdit = canEdit;
  element.canDelete = canEdit;
  const changes = jest.fn();
  element.addEventListener('modelchange', changes);
  document.body.appendChild(element);
  await flush();
  q(element, '[data-id="evidence-toggle"]').click();
  await flush();
  return { element, changes };
}

describe('c-logic-model-evidence', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists an arrow evidence with its strength, and says when there is none', async () => {
    const { element } = await render();
    expect(qa(element, '[data-id="evidence-entry"]')).toHaveLength(1);
    expect(q(element, '[data-id="evidence-entry"]').textContent).toContain('Attendance doubled.');
    expect(q(element, '[data-id="evidence-toggle"]').label).toBe('Assumption Evidence (1)');
    expect(q(element, '.slds-badge').textContent).toBe('Strong');

    const empty = await render('l2');
    expect(qa(empty.element, '[data-id="evidence-entry"]')).toHaveLength(0);
    expect(q(empty.element, 'p')).not.toBeNull();
  });

  it('adds evidence with Moderate as the starting strength and hands back the model', async () => {
    saveEvidence.mockResolvedValue(MODEL);
    const { element, changes } = await render('l2');
    q(element, '[data-id="evidence-add"]').click();
    await flush();
    const summary = q(element, '[data-field="summary"]');
    summary.reportValidity = () => true;
    summary.value = 'Parents said so.';
    summary.dispatchEvent(new CustomEvent('change'));
    q(element, '[data-field="strength"]').reportValidity = () => true;
    for (const field of qa(element, '[data-field]')) {
      field.reportValidity = () => true;
    }
    q(element, '[data-id="evidence-save"]').click();
    await flush();
    const sent = JSON.parse(saveEvidence.mock.calls[0][0].evidenceJson);
    expect(sent.linkId).toBe('l2');
    expect(sent.summary).toBe('Parents said so.');
    expect(sent.strength).toBe('Moderate');
    expect(changes).toHaveBeenCalled();
  });

  it('removes evidence only once confirmed, and a reader cannot add', async () => {
    BarnConfirmModal.open = jest.fn().mockResolvedValue(true);
    remove.mockResolvedValue(MODEL);
    const { element } = await render();
    q(element, '[data-id="evidence-remove"]').click();
    await flush();
    expect(remove).toHaveBeenCalledWith({ recordId: 'e1' });

    const reader = await render('l1', false);
    expect(q(reader.element, '[data-id="evidence-add"]')).toBeNull();
    expect(q(reader.element, '[data-id="evidence-remove"]')).toBeNull();
  });
});
