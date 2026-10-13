import { createElement } from 'lwc';
import StewardshipPlans from 'c/stewardshipPlans';
import getPage from '@salesforce/apex/StewardshipPlanController.getPage';
import saveTemplate from '@salesforce/apex/StewardshipPlanController.saveTemplate';
import setActive from '@salesforce/apex/StewardshipPlanController.setActive';
import saveStep from '@salesforce/apex/StewardshipPlanController.saveStep';
import deleteStep from '@salesforce/apex/StewardshipPlanController.deleteStep';
import reorderSteps from '@salesforce/apex/StewardshipPlanController.reorderSteps';

jest.mock(
  '@salesforce/apex/StewardshipPlanController.getPage',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/StewardshipPlanController.saveTemplate',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/StewardshipPlanController.setActive', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/StewardshipPlanController.saveStep', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/StewardshipPlanController.deleteStep', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/StewardshipPlanController.reorderSteps',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_Stewardship_RunningNotice',
  () => ({
    default:
      'Editing a plan changes what starts next. Plans already running keep the tasks they laid out.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_Stewardship_Empty',
  () => ({ default: 'You have not written a plan down yet.' }),
  { virtual: true }
);

jest.mock('@salesforce/label/c.Giving_Stewardship_Active', () => ({ default: 'On' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Giving_Stewardship_Inactive', () => ({ default: 'Off' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Giving_Stewardship_TurnOn', () => ({ default: 'Turn on' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Giving_Stewardship_TurnOff', () => ({ default: 'Turn off' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Giving_Stewardship_Saved', () => ({ default: 'Saved.' }), {
  virtual: true
});

const WELCOME_ID = 'a06000000000001AAA';
const THANKS_ID = 'a06000000000002AAA';
const STEP_ONE = 'a07000000000001AAA';
const STEP_TWO = 'a07000000000002AAA';

const PAGE = {
  canEdit: true,
  triggerEvents: [
    { label: 'Manual', value: 'Manual' },
    { label: 'First gift', value: 'First gift' },
    { label: 'Commitment started', value: 'Commitment started' }
  ],
  assignTo: [{ label: 'Record owner', value: 'Record owner' }],
  priorities: [{ label: 'Normal', value: 'Normal' }],
  assignableUsers: [{ label: 'Maria Alvarez', value: '005000000000001AAA' }],
  templates: [
    {
      recordId: WELCOME_ID,
      name: 'First gift welcome',
      planKey: 'first_gift_welcome',
      active: true,
      triggerEvent: 'First gift',
      minimumAmount: null,
      description: 'The welcome sequence.',
      runningPlans: 7,
      steps: [
        {
          recordId: STEP_ONE,
          order: 1,
          subject: 'Call to say thank you',
          daysAfterStart: 1,
          assignTo: 'Record owner',
          assignedUserId: null,
          assignedUserName: null,
          priority: 'High',
          comments: null
        },
        {
          recordId: STEP_TWO,
          order: 2,
          subject: 'Send the welcome packet',
          daysAfterStart: 7,
          assignTo: 'Record owner',
          assignedUserId: null,
          assignedUserName: null,
          priority: 'Normal',
          comments: null
        }
      ]
    },
    {
      recordId: THANKS_ID,
      name: 'Major gift thanks',
      planKey: 'major_gift_thanks',
      active: false,
      triggerEvent: 'Gift received',
      minimumAmount: 1000,
      description: null,
      runningPlans: 0,
      steps: []
    }
  ]
};

function createComponent() {
  const element = createElement('c-stewardship-plans', { is: StewardshipPlans });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

function select(element, id) {
  const links = element.shadowRoot.querySelectorAll('[data-id="plan-link"]');
  links[id].click();
  return flush();
}

describe('c-stewardship-plans', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every plan with its steps, its running plans and whether it is on', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const rows = element.shadowRoot.querySelectorAll('[data-id="plan-row"]');
    expect(rows.length).toBe(2);
    const steps = element.shadowRoot.querySelectorAll('[data-id="plan-steps"]');
    expect(steps[0].textContent).toBe('2');
    const running = element.shadowRoot.querySelectorAll('[data-id="plan-running"]');
    expect(running[0].textContent).toBe('7');
    const active = element.shadowRoot.querySelectorAll('[data-id="plan-active"]');
    expect(active[0].textContent).toBe('On');
    expect(active[1].textContent).toBe('Off');
  });

  it('says on the page itself that an edit does not reach a running plan', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="running-notice"]').textContent).toContain(
      'Plans already running keep the tasks they laid out'
    );
  });

  it('tells an administrator with no plans yet to write the first one', async () => {
    const element = createComponent();
    getPage.emit({ ...PAGE, templates: [] });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty-state"]')).not.toBeNull();
  });

  it('shows a plan its steps in order once it is chosen', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    await select(element, 0);

    const subjects = element.shadowRoot.querySelectorAll('[data-id="step-subject"]');
    expect(subjects.length).toBe(2);
    expect(subjects[0].textContent).toBe('Call to say thank you');
    expect(subjects[1].textContent).toBe('Send the welcome packet');
  });

  it('tells a screen reader which plan is chosen, not only by colour', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="plan-selected"]')).toBeNull();
    await select(element, 0);

    const rows = element.shadowRoot.querySelectorAll('[data-id="plan-row"]');
    const marker = rows[0].querySelector('[data-id="plan-selected"]');
    expect(marker.textContent).toBe('c.Giving_Stewardship_Selected');
    expect(rows[1].querySelector('[data-id="plan-selected"]')).toBeNull();
  });

  it('says a plan with no steps would start and lay nothing out', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    await select(element, 1);

    expect(element.shadowRoot.querySelector('[data-id="no-steps"]')).not.toBeNull();
  });

  it('asks for a plan to be chosen until one is, then shows its steps instead', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="select-plan"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="no-steps"]')).toBeNull();

    await select(element, 0);

    expect(element.shadowRoot.querySelector('[data-id="select-plan"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="no-steps"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="step-row"]').length).toBe(2);
  });

  it('creates a plan from the page rather than from an object tab', async () => {
    saveTemplate.mockResolvedValue(WELCOME_ID);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="new-plan"]').click();
    await flush();
    const name = element.shadowRoot.querySelector('[data-id="plan-name"]');
    name.dispatchEvent(new CustomEvent('change', { detail: { value: 'Pledge welcome' } }));
    expect(element.shadowRoot.querySelector('[data-id="plan-key"]')).toBeNull();
    const event = element.shadowRoot.querySelector('[data-id="plan-event-input"]');
    event.dispatchEvent(new CustomEvent('change', { detail: { value: 'Commitment started' } }));
    element.shadowRoot.querySelector('[data-id="save-plan"]').click();
    await flush();

    expect(saveTemplate).toHaveBeenCalledWith({
      template: {
        recordId: null,
        name: 'Pledge welcome',
        triggerEvent: 'Commitment started',
        minimumAmount: null,
        description: '',
        active: false
      }
    });
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]').textContent).toContain(
      'Saved.'
    );
  });

  it('turns a plan off from the list', async () => {
    setActive.mockResolvedValue(undefined);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelectorAll('[data-id="toggle-active"]')[0].click();
    await flush();

    expect(setActive).toHaveBeenCalledWith({ templateId: WELCOME_ID, active: false });
  });

  it('adds a step to the plan that is open', async () => {
    saveStep.mockResolvedValue(STEP_ONE);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    await select(element, 0);

    element.shadowRoot.querySelector('[data-id="add-step"]').click();
    await flush();
    const subject = element.shadowRoot.querySelector('[data-id="step-subject-input"]');
    subject.dispatchEvent(new CustomEvent('change', { detail: { value: 'Check in' } }));
    element.shadowRoot.querySelector('[data-id="save-step"]').click();
    await flush();

    expect(saveStep).toHaveBeenCalledWith({
      templateId: WELCOME_ID,
      step: {
        recordId: null,
        subject: 'Check in',
        daysAfterStart: 0,
        assignTo: 'Record owner',
        assignedUserId: null,
        priority: 'Normal',
        comments: ''
      }
    });
  });

  it('sends the whole order back when a step is moved down', async () => {
    reorderSteps.mockResolvedValue(undefined);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    await select(element, 0);

    element.shadowRoot.querySelectorAll('[data-id="move-down"]')[0].click();
    await flush();

    expect(reorderSteps).toHaveBeenCalledWith({
      templateId: WELCOME_ID,
      stepIds: [STEP_TWO, STEP_ONE]
    });
  });

  it('cannot move the first step up or the last step down', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    await select(element, 0);

    const up = element.shadowRoot.querySelectorAll('[data-id="move-up"]');
    const down = element.shadowRoot.querySelectorAll('[data-id="move-down"]');
    expect(up[0].disabled).toBe(true);
    expect(down[1].disabled).toBe(true);
  });

  it('removes a step from the recipe', async () => {
    deleteStep.mockResolvedValue(undefined);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    await select(element, 0);

    element.shadowRoot.querySelectorAll('[data-id="delete-step"]')[0].click();
    await flush();

    expect(deleteStep).toHaveBeenCalledWith({ stepId: STEP_ONE });
  });

  it('lets a reader read but not change', async () => {
    const element = createComponent();
    getPage.emit({ ...PAGE, canEdit: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="read-only-notice"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="new-plan"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelectorAll('[data-id="edit-plan"]')[0].disabled).toBe(true);
  });

  it('shows the message the platform refused a save with', async () => {
    saveTemplate.mockRejectedValue({
      body: { message: 'A minimum amount means nothing on a manual plan.' }
    });
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelectorAll('[data-id="edit-plan"]')[0].click();
    await flush();
    element.shadowRoot.querySelector('[data-id="save-plan"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toContain(
      'A minimum amount means nothing on a manual plan.'
    );
  });
});
