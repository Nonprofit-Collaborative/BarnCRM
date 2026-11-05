import { createElement } from 'lwc';
import LogicModelPeriods from 'c/logicModelPeriods';
import savePeriods from '@salesforce/apex/LogicModelBuilderController.savePeriods';
import addPeriodToEveryIndicator from '@salesforce/apex/LogicModelBuilderController.addPeriodToEveryIndicator';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock(
  '@salesforce/apex/LogicModelBuilderController.savePeriods',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/LogicModelBuilderController.addPeriodToEveryIndicator',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const Q1 = Object.freeze({ name: '2026 Q1', startDate: '2026-01-01', endDate: '2026-03-31' });
const Q2 = Object.freeze({ name: '2026 Q2', startDate: '2026-04-01', endDate: '2026-06-30' });
const MODEL = Object.freeze({ id: 'm1', canEditPeriods: true, periods: [Q1, Q2] });

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

async function render(model = MODEL, canEdit = true) {
  const element = createElement('c-logic-model-periods', { is: LogicModelPeriods });
  element.model = model;
  element.canEdit = canEdit;
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

describe('c-logic-model-periods', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists the model's reporting periods", async () => {
    const { element } = await render();
    expect(qa(element, 'model-period')).toHaveLength(2);
    expect(q(element, 'no-model-periods')).toBeNull();
    expect(qa(element, 'add-to-every')).toHaveLength(2);
  });

  it('says when there are none', async () => {
    const { element } = await render({ id: 'm1', canEditPeriods: true, periods: [] });
    expect(q(element, 'no-model-periods')).not.toBeNull();
    expect(q(element, 'add-model-period')).not.toBeNull();
  });

  it('adds a period to the list', async () => {
    savePeriods.mockResolvedValue(MODEL);
    const { element, changes } = await render();
    q(element, 'add-model-period').click();
    await flush();
    expect(q(element, 'model-period-save').disabled).toBe(true);
    change(q(element, 'model-period-name'), ' 2026 Q3 ');
    change(q(element, 'model-period-start'), '2026-07-01');
    change(q(element, 'model-period-end'), '2026-09-30');
    await flush();
    q(element, 'model-period-save').click();
    await flush();
    expect(savePeriods.mock.calls[0][0].modelId).toBe('m1');
    expect(JSON.parse(savePeriods.mock.calls[0][0].periodsJson)).toEqual([
      Q1,
      Q2,
      { name: '2026 Q3', startDate: '2026-07-01', endDate: '2026-09-30' }
    ]);
    expect(changes).toHaveBeenCalledTimes(1);
    expect(q(element, 'model-period-form')).toBeNull();
  });

  it('passes a refusal up and keeps the form open', async () => {
    savePeriods.mockRejectedValue({ body: { message: 'Same dates.' } });
    const { element, failures } = await render();
    q(element, 'add-model-period').click();
    await flush();
    change(q(element, 'model-period-name'), 'Again');
    change(q(element, 'model-period-start'), '2026-01-01');
    change(q(element, 'model-period-end'), '2026-03-31');
    await flush();
    q(element, 'model-period-save').click();
    await flush();
    expect(failures.mock.calls[0][0].detail.message).toBe('Same dates.');
    expect(q(element, 'model-period-form')).not.toBeNull();
    q(element, 'model-period-cancel').click();
    await flush();
    expect(q(element, 'model-period-form')).toBeNull();
  });

  it('removes a period after a confirm in a modal, and not without one', async () => {
    savePeriods.mockResolvedValue(MODEL);
    const { element, changes } = await render();
    BarnConfirmModal.open.mockResolvedValue(false);
    qa(element, 'remove-model-period')[0].click();
    await flush();
    expect(savePeriods).not.toHaveBeenCalled();
    BarnConfirmModal.open.mockResolvedValue(true);
    qa(element, 'remove-model-period')[0].click();
    await flush();
    expect(BarnConfirmModal.open.mock.calls[1][0]).toMatchObject({
      confirmVariant: 'destructive',
      message: 'c.LogicModels_Periods_DeleteConfirm'
    });
    expect(JSON.parse(savePeriods.mock.calls[0][0].periodsJson)).toEqual([Q2]);
    expect(changes).toHaveBeenCalledTimes(1);
  });

  it('adds a period to every indicator and says how many', async () => {
    addPeriodToEveryIndicator.mockResolvedValue({ ...MODEL, added: 3 });
    const { element, changes } = await render();
    qa(element, 'add-to-every')[1].click();
    await flush();
    expect(addPeriodToEveryIndicator).toHaveBeenCalledWith({
      modelId: 'm1',
      startDate: '2026-04-01',
      endDate: '2026-06-30'
    });
    expect(changes.mock.calls[0][0].detail.message).toBe('c.LogicModels_Periods_Added');
  });

  it('shows a reader the list without changes', async () => {
    const { element } = await render({ ...MODEL, canEditPeriods: false }, false);
    expect(qa(element, 'model-period')).toHaveLength(2);
    expect(q(element, 'add-model-period')).toBeNull();
    expect(q(element, 'remove-model-period')).toBeNull();
    expect(q(element, 'add-to-every')).toBeNull();
  });
});
