import { createElement } from 'lwc';
import RollupTemplates from 'c/rollupTemplates';
import getTemplates from '@salesforce/apex/RollupTemplates.getTemplates';
import addRollups from '@salesforce/apex/RollupTemplates.addRollups';

jest.mock('@salesforce/apex/RollupTemplates.getTemplates', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupTemplates.addRollups', () => ({ default: jest.fn() }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const AVERAGE_DRAFT = {
  name: 'Average Gift',
  targetObject: 'Contact',
  targetField: 'Average_Gift__c',
  sourceObject: 'Gift__c',
  aggregate: 'AVG',
  active: false
};

const TEMPLATES = [
  {
    key: 'nonprofitStarter',
    name: 'Nonprofit Starter',
    description: 'Common totals Giving does not ship.',
    items: [
      {
        key: 'averageGift',
        name: 'Average Gift',
        sentence: 'Average of Amount from Gifts by Donor.',
        status: 'Create the Average Gift field on Contact first.',
        available: false,
        needsField: true,
        canOpen: true,
        fieldLabel: 'Average Gift',
        fieldKind: 'CURRENCY',
        draft: AVERAGE_DRAFT
      },
      {
        key: 'smallestGift',
        name: 'Smallest Gift',
        sentence: 'Smallest Amount from Gifts by Donor.',
        status: 'Ready to add.',
        available: true,
        needsField: false,
        canOpen: true,
        fieldLabel: 'Smallest Gift',
        fieldKind: 'CURRENCY',
        draft: { ...AVERAGE_DRAFT, name: 'Smallest Gift', targetField: 'Smallest_Gift__c' }
      }
    ]
  }
];

async function build(canManage = true) {
  getTemplates.mockResolvedValue(TEMPLATES);
  const element = createElement('c-rollup-templates', { is: RollupTemplates });
  element.canManage = canManage;
  document.body.appendChild(element);
  await flush();
  return element;
}

const query = (element, selector) => element.shadowRoot.querySelector(selector);
const all = (element, selector) => Array.from(element.shadowRoot.querySelectorAll(selector));

async function openPanel(element) {
  query(element, '[data-id="toggle"]').click();
  await flush();
}

describe('c-rollup-templates', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows nothing to someone who cannot manage settings', async () => {
    const element = await build(false);
    expect(query(element, '[data-id="toggle"]')).toBeNull();
    expect(getTemplates).not.toHaveBeenCalled();
  });

  it('loads nothing and adds nothing until opened (U2)', async () => {
    const element = await build();
    expect(getTemplates).not.toHaveBeenCalled();
    expect(query(element, '[data-id="templates"]')).toBeNull();
    expect(addRollups).not.toHaveBeenCalled();
  });

  it('lists each rollup unticked, with its status, and only ready ones can be ticked', async () => {
    const element = await build();
    await openPanel(element);

    expect(getTemplates).toHaveBeenCalledTimes(1);
    const boxes = all(element, '[data-role="choose"]');
    expect(boxes).toHaveLength(2);
    boxes.forEach((box) => expect(box.checked).toBe(false));
    expect(boxes[0].disabled).toBe(true);
    expect(boxes[1].disabled).toBe(false);
    expect(all(element, '[data-role="status"]').map((node) => node.textContent)).toEqual([
      'Create the Average Gift field on Contact first.',
      'Ready to add.'
    ]);
    expect(query(element, '[data-id="add"]').disabled).toBe(true);
  });

  it('adds only the ticked rollups, then reloads and tells the Builder', async () => {
    addRollups.mockResolvedValue([{ name: 'Smallest Gift', added: true, message: 'Added, off.' }]);
    const element = await build();
    const added = jest.fn();
    element.addEventListener('added', added);
    await openPanel(element);

    const box = query(element, '[data-id="nonprofitStarter.smallestGift"][data-role="choose"]');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(query(element, '[data-id="add"]').disabled).toBe(false);

    query(element, '[data-id="add"]').click();
    await flush();
    await flush();

    expect(addRollups).toHaveBeenCalledWith({
      templateKey: 'nonprofitStarter',
      itemKeys: ['smallestGift']
    });
    expect(all(element, '[data-role="outcome"]').map((node) => node.textContent)).toEqual([
      'Smallest Gift: Added, off.'
    ]);
    expect(getTemplates).toHaveBeenCalledTimes(2);
    expect(added).toHaveBeenCalledTimes(1);
    expect(query(element, '[data-id="add"]').disabled).toBe(true);
  });

  it('opens a rollup in the Builder with the field to create (U2, U8)', async () => {
    const element = await build();
    const opened = jest.fn();
    element.addEventListener('open', opened);
    await openPanel(element);

    query(element, '[data-id="nonprofitStarter.averageGift"][data-role="open"]').click();

    expect(opened).toHaveBeenCalledTimes(1);
    expect(opened.mock.calls[0][0].detail.draft).toEqual({
      ...AVERAGE_DRAFT,
      newFieldLabel: 'Average Gift',
      newFieldKind: 'CURRENCY'
    });
  });

  it('shows the reason when the templates cannot be read', async () => {
    getTemplates.mockReset();
    getTemplates.mockRejectedValue({ body: { message: 'No permission.' } });
    const element = createElement('c-rollup-templates', { is: RollupTemplates });
    element.canManage = true;
    document.body.appendChild(element);
    await openPanel(element);

    expect(query(element, '[data-id="error"]').textContent).toBe('No permission.');
  });
});
