import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import StewardshipPlanStart from 'c/stewardshipPlanStart';
import getStartable from '@salesforce/apex/StewardshipStartController.getStartable';
import startPlan from '@salesforce/apex/StewardshipStartController.startPlan';

jest.mock(
  '@salesforce/apex/StewardshipStartController.getStartable',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/StewardshipStartController.startPlan',
  () => ({ default: jest.fn(() => Promise.resolve('a05000000000001')) }),
  { virtual: true }
);

const DONOR_ID = '003000000000001';
const PLANS = {
  canStart: true,
  plans: [
    { label: 'Major gift thanks', value: 'a04000000000001', description: 'After a meeting' },
    { label: 'First gift welcome', value: 'a04000000000002', description: null }
  ]
};

function build() {
  const element = createElement('c-stewardship-plan-start', { is: StewardshipPlanStart });
  element.recordId = DONOR_ID;
  document.body.appendChild(element);
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function flush() {
  return Promise.resolve();
}

describe('c-stewardship-plan-start', () => {
  let toast;

  beforeEach(() => {
    toast = jest.spyOn(Toast, 'show');
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the plans and shows what the chosen one is for', async () => {
    const element = build();
    getStartable.emit(PLANS);
    await flush();

    const picker = find(element, 'plan');
    expect(picker.options.length).toBe(2);
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'a04000000000001' } }));
    await flush();

    expect(find(element, 'description').textContent).toBe('After a meeting');
  });

  it('starts the chosen plan on this donor', async () => {
    const element = build();
    getStartable.emit(PLANS);
    await flush();

    find(element, 'plan').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'a04000000000002' } })
    );
    find(element, 'start').click();
    await flush();
    await flush();

    expect(startPlan).toHaveBeenCalledWith({
      templateId: 'a04000000000002',
      donorId: DONOR_ID
    });
    expect(toast.mock.calls[0][0].variant).toBe('success');
  });

  it('asks for a plan before it starts anything', async () => {
    const element = build();
    getStartable.emit(PLANS);
    await flush();

    find(element, 'start').click();
    await flush();

    expect(startPlan).not.toHaveBeenCalled();
    expect(toast.mock.calls[0][0].label).toBe('c.Giving_Stewardship_StartChooseFirst');
  });

  it('shows the reason the server gives for not starting', async () => {
    startPlan.mockImplementationOnce(() =>
      Promise.reject({ body: { message: 'This plan is already running for this donor.' } })
    );
    const element = build();
    getStartable.emit(PLANS);
    await flush();

    find(element, 'plan').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'a04000000000001' } })
    );
    find(element, 'start').click();
    await flush();
    await flush();

    expect(toast.mock.calls[0][0].label).toContain('already running');
  });

  it('tells a reader they cannot start a plan, and offers no Start', async () => {
    const element = build();
    getStartable.emit({ ...PLANS, canStart: false });
    await flush();

    expect(find(element, 'no-access')).not.toBeNull();
    expect(find(element, 'start')).toBeNull();
  });

  it('says so when no plan is turned on', async () => {
    const element = build();
    getStartable.emit({ canStart: true, plans: [] });
    await flush();

    expect(find(element, 'no-plans')).not.toBeNull();
    expect(find(element, 'start')).toBeNull();
  });
});
