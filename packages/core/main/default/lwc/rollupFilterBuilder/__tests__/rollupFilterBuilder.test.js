import { createElement } from 'lwc';
import RollupFilterBuilder from 'c/rollupFilterBuilder';

jest.mock('@salesforce/label/c.Core_RollupFilter_Whose', () => ({ default: '{0} whose {1}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RollupFilter_And', () => ({ default: 'and' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RollupFilter_Or', () => ({ default: 'or' }), { virtual: true });
jest.mock(
  '@salesforce/label/c.Core_RollupFilter_EveryRecord',
  () => ({ default: 'Every record counts.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_RollupFilter_OpEquals', () => ({ default: 'is' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RollupFilter_OpIn', () => ({ default: 'is one of' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupFilter_OpGreaterThan',
  () => ({ default: 'is greater than' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_RollupFilter_OpIsNull', () => ({ default: 'is blank' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupFilter_ErrorIncomplete',
  () => ({ default: 'Condition {0} is missing something.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_RollupFilter_ErrorLogic',
  () => ({ default: 'Use only the numbers 1 to {0}.' }),
  { virtual: true }
);

const FIELDS = [
  {
    value: 'Status__c',
    label: 'Status',
    type: 'picklist',
    picklistValues: [
      { value: 'Received', label: 'Received' },
      { value: 'Refunded', label: 'Refunded' },
      { value: 'Pending', label: 'Pending' }
    ]
  },
  { value: 'Amount__c', label: 'Amount', type: 'currency' },
  { value: 'Gift_Date__c', label: 'Gift Date', type: 'date' },
  { value: 'Anonymous__c', label: 'Anonymous', type: 'boolean' }
];

const DOCUMENT = {
  version: 1,
  conditions: [
    { id: 1, field: 'Status__c', operator: 'in', value: ['Received', 'Refunded'] },
    { id: 2, field: 'Amount__c', operator: 'greater than', value: 0 }
  ]
};

function build(value) {
  const element = createElement('c-rollup-filter-builder', { is: RollupFilterBuilder });
  element.fields = FIELDS;
  element.recordsLabel = 'Gifts';
  element.value = value === undefined ? JSON.stringify(DOCUMENT) : value;
  document.body.appendChild(element);
  return element;
}

function changeValue(element, selector, value) {
  const input = element.shadowRoot.querySelector(selector);
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-rollup-filter-builder', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('reads a filter document back as a sentence', () => {
    const element = build();
    const sentence = element.shadowRoot.querySelector('[data-id="sentence"]');
    expect(sentence.textContent).toBe(
      'Gifts whose Status is one of Received or Refunded and Amount is greater than 0'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="condition"]')).toHaveLength(2);
  });

  it('says every record counts when there are no conditions', () => {
    const element = build(null);
    expect(element.shadowRoot.querySelector('[data-id="sentence"]').textContent).toBe(
      'Every record counts.'
    );
    expect(element.value).toBeNull();
  });

  it('follows the logic string in the sentence and the document', async () => {
    const element = build(JSON.stringify({ ...DOCUMENT, logic: '1 OR 2' }));
    await Promise.resolve();
    expect(element.shadowRoot.querySelector('[data-id="sentence"]').textContent).toBe(
      'Gifts whose Status is one of Received or Refunded or Amount is greater than 0'
    );
    expect(JSON.parse(element.value).logic).toBe('1 OR 2');
  });

  it('adds a condition, fills it in, and fires the new document', async () => {
    const element = build(null);
    const handler = jest.fn();
    element.addEventListener('change', handler);

    element.shadowRoot.querySelector('[data-id="add-condition"]').click();
    await Promise.resolve();
    changeValue(element, '[data-role="field"]', 'Amount__c');
    await Promise.resolve();
    changeValue(element, '[data-role="value"]', '250');
    await Promise.resolve();

    const fired = JSON.parse(handler.mock.calls[handler.mock.calls.length - 1][0].detail.value);
    expect(fired).toEqual({
      version: 1,
      conditions: [{ id: 1, field: 'Amount__c', operator: 'equals', value: 250 }]
    });
  });

  it('writes a typed list of values for one of', async () => {
    const element = build(null);
    element.shadowRoot.querySelector('[data-id="add-condition"]').click();
    await Promise.resolve();
    changeValue(element, '[data-role="field"]', 'Amount__c');
    await Promise.resolve();
    changeValue(element, '[data-role="operator"]', 'in');
    await Promise.resolve();
    changeValue(element, '[data-role="value"]', '10, 20');
    await Promise.resolve();
    expect(JSON.parse(element.value).conditions[0].value).toEqual([10, 20]);
  });

  it('writes no value for is blank, and a true checkbox as true', async () => {
    const element = build(
      JSON.stringify({
        version: 1,
        conditions: [
          { id: 1, field: 'Gift_Date__c', operator: 'is null' },
          { id: 2, field: 'Anonymous__c', operator: 'equals', value: false }
        ]
      })
    );
    await Promise.resolve();
    changeValue(element, '[data-role="value"]', 'true');
    await Promise.resolve();
    const conditions = JSON.parse(element.value).conditions;
    expect(conditions[0]).toEqual({ id: 1, field: 'Gift_Date__c', operator: 'is null' });
    expect(conditions[1].value).toBe(true);
  });

  it('removes a condition, renumbers the rest and clears the logic', async () => {
    const element = build(JSON.stringify({ ...DOCUMENT, logic: '1 AND 2' }));
    await Promise.resolve();
    element.shadowRoot.querySelector('[data-role="remove"]').click();
    await Promise.resolve();
    const remaining = JSON.parse(element.value);
    expect(remaining.conditions).toEqual([
      { id: 1, field: 'Amount__c', operator: 'greater than', value: 0 }
    ]);
    expect(remaining.logic).toBeUndefined();
  });

  it('validates a missing value and a logic string naming an unknown condition', async () => {
    const element = build(null);
    element.shadowRoot.querySelector('[data-id="add-condition"]').click();
    await Promise.resolve();
    changeValue(element, '[data-role="field"]', 'Amount__c');
    await Promise.resolve();
    expect(element.validate()).toBe('Condition 1 is missing something.');

    element.value = JSON.stringify({ ...DOCUMENT, logic: '1 AND 3' });
    expect(element.validate()).toBe('Use only the numbers 1 to 2.');

    element.value = JSON.stringify(DOCUMENT);
    expect(element.validate()).toBeNull();
  });
});
