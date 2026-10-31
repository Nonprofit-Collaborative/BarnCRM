import { createElement } from 'lwc';
import LogicModelBuilder from 'c/logicModelBuilder';
import getModel from '@salesforce/apex/LogicModelBuilderController.getModel';
import getPrograms from '@salesforce/apex/LogicModelBuilderController.getPrograms';
import setProgram from '@salesforce/apex/LogicModelBuilderController.setProgram';
import saveElement from '@salesforce/apex/LogicModelBuilderController.saveElement';

jest.mock('@salesforce/apex/LogicModelBuilderController.getModel', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/LogicModelBuilderController.getPrograms',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/LogicModelBuilderController.setProgram',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/LogicModelBuilderController.saveElement',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.LogicModels_Builder_AddTo', () => ({ default: 'Add to {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.LogicModels_Stage_Input', () => ({ default: 'Inputs' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.LogicModels_Builder_FindingNoIn',
  () => ({ default: 'No arrow into {0}' }),
  {
    virtual: true
  }
);

const MODEL_ID = 'a0L000000000001AAA';

const model = (extra = {}) => ({
  id: MODEL_ID,
  name: 'Reading',
  programId: null,
  programsAvailable: true,
  canEdit: true,
  canDelete: true,
  elements: [{ id: 'e1', name: 'Tutors', type: 'Input', sortOrder: 10 }],
  links: [],
  indicators: [],
  ...extra
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(value = model()) {
  getModel.mockResolvedValue(value);
  const element = createElement('c-logic-model-builder', { is: LogicModelBuilder });
  element.recordId = MODEL_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('c-logic-model-builder', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws seven columns, the parts and what needs attention', async () => {
    const element = await render();
    expect(getModel).toHaveBeenCalledWith({ modelId: MODEL_ID });
    expect(qa(element, 'column')).toHaveLength(7);
    expect(qa(element, 'part')).toHaveLength(1);
    expect(qa(element, 'add')[0].label).toBe('Add to Inputs');
    expect(q(element, 'scope-name').textContent).toBe('c.LogicModels_Builder_WholeOrganization');
    expect(q(element, 'findings')).not.toBeNull();
    expect(q(element, 'select-hint')).not.toBeNull();
  });

  it('shows the part panel for the selected part', async () => {
    const element = await render();
    const part = q(element, 'part');
    part.click();
    await flush();
    expect(part.getAttribute('aria-pressed')).toBe('true');
    const panel = q(element, 'selected-part');
    expect(panel).not.toBeNull();
    panel.dispatchEvent(
      new CustomEvent('modelchange', {
        detail: { model: model({ elements: [] }), message: 'Deleted.' }
      })
    );
    await flush();
    expect(q(element, 'result').textContent).toBe('Deleted.');
    expect(qa(element, 'part')).toHaveLength(0);
  });

  it('adds a part at the end of a column', async () => {
    const element = await render();
    saveElement.mockResolvedValue(
      model({
        elements: [...model().elements, { id: 'e2', name: 'Books', type: 'Input', sortOrder: 20 }]
      })
    );
    qa(element, 'add')[0].click();
    await flush();
    const name = q(element, 'draft-name');
    name.value = 'Books';
    name.dispatchEvent(new CustomEvent('change'));
    await flush();
    q(element, 'add-save').click();
    await flush();
    expect(JSON.parse(saveElement.mock.calls[0][0].elementJson)).toEqual({
      modelId: MODEL_ID,
      name: 'Books',
      type: 'Input',
      term: null,
      sortOrder: 20
    });
    expect(qa(element, 'part')).toHaveLength(2);
    expect(q(element, 'add-form')).toBeNull();
  });

  it('shows a refused save in its own words', async () => {
    const element = await render();
    saveElement.mockRejectedValue({ body: { message: 'Name is required.' } });
    qa(element, 'add')[0].click();
    await flush();
    const name = q(element, 'draft-name');
    name.value = 'X';
    name.dispatchEvent(new CustomEvent('change'));
    await flush();
    q(element, 'add-save').click();
    await flush();
    expect(q(element, 'error-message').textContent.trim()).toBe('Name is required.');
    q(element, 'add-cancel').click();
    await flush();
    expect(q(element, 'add-form')).toBeNull();
  });

  it('changes whose model it is', async () => {
    const element = await render();
    getPrograms.mockResolvedValue([{ value: 'p1', label: 'After School' }]);
    setProgram.mockResolvedValue(model({ programId: 'p1', programName: 'After School' }));
    q(element, 'change-scope').click();
    await flush();
    const picker = q(element, 'scope-picker');
    expect(picker.options).toHaveLength(2);
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'p1' } }));
    q(element, 'scope-save').click();
    await flush();
    expect(setProgram).toHaveBeenCalledWith({ modelId: MODEL_ID, programId: 'p1' });
    expect(q(element, 'scope-name').textContent).toBe('After School');
    expect(q(element, 'scope-form')).toBeNull();
  });

  it('names a missing program and hides editing from a reader', async () => {
    const element = await render(model({ programId: 'p9', programMissing: true, canEdit: false }));
    expect(q(element, 'scope-name').textContent).toBe('c.LogicModels_Builder_ProgramMissing');
    expect(q(element, 'change-scope')).toBeNull();
    expect(qa(element, 'add')).toHaveLength(0);
  });

  it('shows a failed load', async () => {
    getModel.mockRejectedValue(new Error('down'));
    const element = createElement('c-logic-model-builder', { is: LogicModelBuilder });
    element.recordId = MODEL_ID;
    document.body.appendChild(element);
    await flush();
    expect(q(element, 'error-message').textContent.trim()).toBe(
      'c.LogicModels_Builder_ActionFailed'
    );
    expect(q(element, 'columns')).toBeNull();
  });
});
