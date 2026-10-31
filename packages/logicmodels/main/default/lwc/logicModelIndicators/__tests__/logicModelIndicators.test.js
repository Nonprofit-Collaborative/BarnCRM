import { createElement } from 'lwc';
import LogicModelIndicators from 'c/logicModelIndicators';
import saveIndicator from '@salesforce/apex/LogicModelBuilderController.saveIndicator';
import savePeriod from '@salesforce/apex/LogicModelBuilderController.savePeriod';
import remove from '@salesforce/apex/LogicModelBuilderController.remove';

jest.mock(
  '@salesforce/apex/LogicModelBuilderController.saveIndicator',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/LogicModelBuilderController.savePeriod',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/LogicModelBuilderController.remove', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.LogicModels_Period_Met', () => ({ default: 'Met' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.LogicModels_Period_Percent', () => ({ default: '{0}%' }), {
  virtual: true
});

const MODEL = Object.freeze({
  id: 'm1',
  elements: [{ id: 'c1', name: 'Reads more', type: 'Outcome', term: 'Short Term' }],
  links: [],
  indicators: [
    {
      id: 'i1',
      elementId: 'c1',
      name: 'Students reading daily',
      unit: 'students',
      betterWhen: 'Higher',
      baselineValue: 10,
      periods: [
        {
          id: 'p1',
          name: 'Q1',
          startDate: '2026-01-01',
          endDate: '2026-03-31',
          targetValue: 30,
          resultValue: 20
        },
        {
          id: 'p2',
          name: 'Q2',
          startDate: '2026-04-01',
          endDate: '2026-06-30',
          targetValue: 30,
          resultValue: 35
        }
      ]
    },
    { id: 'i9', elementId: 'other', name: 'Not here', periods: [] }
  ]
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

async function render(canEdit = true) {
  const element = createElement('c-logic-model-indicators', { is: LogicModelIndicators });
  element.model = MODEL;
  element.elementId = 'c1';
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

describe('c-logic-model-indicators', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists the part's indicators with progress per period", async () => {
    const { element } = await render();
    expect(qa(element, 'indicator')).toHaveLength(1);
    expect(Array.from(qa(element, 'progress')).map((cell) => cell.textContent)).toEqual([
      '50%',
      'Met'
    ]);
  });

  it('adds an indicator to the part', async () => {
    const { element, changes } = await render();
    saveIndicator.mockResolvedValue(MODEL);
    q(element, 'add-indicator').click();
    await flush();
    change(q(element, 'indicator-name'), 'Books finished');
    change(q(element, 'indicator-better-when'), 'Lower');
    await flush();
    q(element, 'indicator-save').click();
    await flush();
    expect(JSON.parse(saveIndicator.mock.calls[0][0].indicatorJson)).toMatchObject({
      elementId: 'c1',
      name: 'Books finished',
      betterWhen: 'Lower'
    });
    expect(changes).toHaveBeenCalledTimes(1);
    expect(q(element, 'indicator-form')).toBeNull();
  });

  it('edits an indicator', async () => {
    const { element } = await render();
    saveIndicator.mockResolvedValue(MODEL);
    q(element, 'indicator-edit').click();
    await flush();
    expect(q(element, 'indicator-name').value).toBe('Students reading daily');
    q(element, 'indicator-save').click();
    await flush();
    expect(JSON.parse(saveIndicator.mock.calls[0][0].indicatorJson).id).toBe('i1');
  });

  it('adds a period and passes a refusal up', async () => {
    const { element, failures } = await render();
    savePeriod.mockRejectedValue({ body: { message: 'That period exists.' } });
    q(element, 'add-period').click();
    await flush();
    change(q(element, 'period-name'), 'Q3');
    change(q(element, 'period-start'), '2026-07-01');
    change(q(element, 'period-end'), '2026-09-30');
    change(q(element, 'period-target'), 30);
    await flush();
    q(element, 'period-save').click();
    await flush();
    expect(JSON.parse(savePeriod.mock.calls[0][0].periodJson)).toMatchObject({
      indicatorId: 'i1',
      name: 'Q3',
      startDate: '2026-07-01',
      endDate: '2026-09-30',
      targetValue: 30
    });
    expect(failures.mock.calls[0][0].detail.message).toBe('That period exists.');
  });

  it('edits and deletes a period', async () => {
    const { element } = await render();
    savePeriod.mockResolvedValue(MODEL);
    remove.mockResolvedValue(MODEL);
    qa(element, 'period-edit')[1].click();
    await flush();
    change(q(element, 'period-result'), 40);
    q(element, 'period-save').click();
    await flush();
    expect(JSON.parse(savePeriod.mock.calls[0][0].periodJson)).toMatchObject({
      id: 'p2',
      resultValue: 40
    });
    qa(element, 'period-delete')[0].click();
    await flush();
    expect(remove).toHaveBeenCalledWith({ recordId: 'p1' });
  });

  it('deletes an indicator after a confirm', async () => {
    const { element, changes } = await render();
    remove.mockResolvedValue(MODEL);
    q(element, 'indicator-delete').click();
    await flush();
    q(element, 'indicator-delete-confirm-button').click();
    await flush();
    expect(remove).toHaveBeenCalledWith({ recordId: 'i1' });
    expect(changes).toHaveBeenCalledTimes(1);
  });

  it('offers no changes to a reader', async () => {
    const { element } = await render(false);
    expect(q(element, 'add-indicator')).toBeNull();
    expect(q(element, 'period-edit')).toBeNull();
  });
});
