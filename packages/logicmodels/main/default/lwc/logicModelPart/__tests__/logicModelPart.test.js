import { createElement } from 'lwc';
import LogicModelPart from 'c/logicModelPart';
import saveElement from '@salesforce/apex/LogicModelBuilderController.saveElement';
import saveOrder from '@salesforce/apex/LogicModelBuilderController.saveOrder';
import saveLink from '@salesforce/apex/LogicModelBuilderController.saveLink';
import remove from '@salesforce/apex/LogicModelBuilderController.remove';

jest.mock(
  '@salesforce/apex/LogicModelBuilderController.saveElement',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/LogicModelBuilderController.saveOrder',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/LogicModelBuilderController.saveLink', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/LogicModelBuilderController.remove', () => ({ default: jest.fn() }), {
  virtual: true
});

const MODEL = Object.freeze({
  id: 'm1',
  elements: [
    { id: 'a1', name: 'Sessions', type: 'Activity', sortOrder: 10 },
    { id: 'a2', name: 'Calls', type: 'Activity', sortOrder: 20 },
    { id: 'o1', name: 'Sessions held', type: 'Output', sortOrder: 10 },
    { id: 'c1', name: 'Reads more', type: 'Outcome', term: 'Short Term', sortOrder: 10 }
  ],
  links: [{ id: 'l1', fromId: 'a1', toId: 'o1', assumption: 'Kids come.' }],
  indicators: []
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

async function render(elementId = 'a1', canEdit = true) {
  const element = createElement('c-logic-model-part', { is: LogicModelPart });
  element.model = MODEL;
  element.elementId = elementId;
  element.canEdit = canEdit;
  element.canDelete = canEdit;
  const changes = jest.fn();
  const failures = jest.fn();
  element.addEventListener('modelchange', changes);
  element.addEventListener('failure', failures);
  document.body.appendChild(element);
  await flush();
  return { element, changes, failures };
}

function change(target, value) {
  target.value = value;
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-logic-model-part', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the part and its arrows with their assumptions', async () => {
    const { element } = await render();
    expect(q(element, 'part-name').textContent).toBe('Sessions');
    expect(qa(element, 'arrow')).toHaveLength(1);
    expect(q(element, 'move-up').disabled).toBe(true);
    expect(q(element, 'move-down').disabled).toBe(false);
    expect(q(element, 'indicators')).toBeNull();
  });

  it('edits the name and column', async () => {
    const { element, changes } = await render();
    saveElement.mockResolvedValue(MODEL);
    q(element, 'edit').click();
    await flush();
    change(q(element, 'edit-name'), 'Weekly sessions');
    change(q(element, 'edit-stage'), 'Output');
    await flush();
    q(element, 'edit-save').click();
    await flush();
    expect(JSON.parse(saveElement.mock.calls[0][0].elementJson)).toMatchObject({
      id: 'a1',
      name: 'Weekly sessions',
      type: 'Output',
      term: null
    });
    expect(changes).toHaveBeenCalledTimes(1);
    expect(q(element, 'edit-form')).toBeNull();
  });

  it('moves the part down its column', async () => {
    const { element } = await render();
    saveOrder.mockResolvedValue(MODEL);
    q(element, 'move-down').click();
    await flush();
    expect(saveOrder).toHaveBeenCalledWith({
      modelId: 'm1',
      ordersJson: JSON.stringify([
        { id: 'a2', sortOrder: 10 },
        { id: 'a1', sortOrder: 20 }
      ])
    });
  });

  it('adds an arrow forward with an assumption', async () => {
    const { element, failures } = await render();
    saveLink.mockRejectedValue({ body: { message: 'Already linked.' } });
    q(element, 'add-arrow').click();
    await flush();
    const target = q(element, 'arrow-target');
    expect(target.options.map((option) => option.value)).toEqual(['c1']);
    change(target, 'c1');
    change(q(element, 'arrow-assumption'), 'Reading sticks.');
    await flush();
    q(element, 'arrow-save').click();
    await flush();
    expect(JSON.parse(saveLink.mock.calls[0][0].linkJson)).toEqual({
      modelId: 'm1',
      fromId: 'a1',
      toId: 'c1',
      assumption: 'Reading sticks.'
    });
    expect(failures.mock.calls[0][0].detail.message).toBe('Already linked.');
  });

  it('changes an assumption and removes an arrow', async () => {
    const { element, changes } = await render();
    saveLink.mockResolvedValue(MODEL);
    remove.mockResolvedValue(MODEL);
    q(element, 'link-edit').click();
    await flush();
    change(q(element, 'link-assumption'), 'Most kids come.');
    q(element, 'link-save').click();
    await flush();
    expect(JSON.parse(saveLink.mock.calls[0][0].linkJson)).toEqual({
      id: 'l1',
      assumption: 'Most kids come.'
    });
    q(element, 'link-remove').click();
    await flush();
    expect(remove).toHaveBeenCalledWith({ recordId: 'l1' });
    expect(changes).toHaveBeenCalledTimes(2);
  });

  it('deletes the part after a confirm', async () => {
    const { element, changes } = await render();
    remove.mockResolvedValue(MODEL);
    q(element, 'delete').click();
    await flush();
    q(element, 'delete-confirm-button').click();
    await flush();
    expect(remove).toHaveBeenCalledWith({ recordId: 'a1' });
    expect(changes.mock.calls[0][0].detail.message).toBe('c.LogicModels_Builder_Deleted');
  });

  it('shows indicators for an output and passes their saves up', async () => {
    const { element, changes } = await render('o1');
    const indicators = q(element, 'indicators');
    expect(indicators).not.toBeNull();
    indicators.dispatchEvent(new CustomEvent('modelchange', { detail: { model: MODEL } }));
    expect(changes).toHaveBeenCalledTimes(1);
  });

  it('offers no changes to a reader', async () => {
    const { element } = await render('a1', false);
    expect(q(element, 'part-actions')).toBeNull();
    expect(q(element, 'add-arrow')).toBeNull();
  });
});
