import { createElement } from 'lwc';
import SetupAssistant from 'c/setupAssistant';
import getState from '@salesforce/apex/SetupAssistantController.getState';
import completeStep from '@salesforce/apex/SetupAssistantController.completeStep';
import skipStep from '@salesforce/apex/SetupAssistantController.skipStep';
import applyCoexistence from '@salesforce/apex/SetupAssistantController.applyCoexistence';
import saveStepValues from '@salesforce/apex/SetupAssistantController.saveStepValues';
import assignAccess from '@salesforce/apex/SetupAssistantController.assignAccess';
import resetSetup from '@salesforce/apex/SetupAssistantController.reset';

jest.mock('@salesforce/apex/SetupAssistantController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/SetupAssistantController.completeStep',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/SetupAssistantController.skipStep', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SetupAssistantController.reset', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/SetupAssistantController.applyCoexistence',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/SetupAssistantController.saveStepValues',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/SetupAssistantController.assignAccess',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const STEP_DEFINITIONS = [
  ['coexistence', 'Confirm how Open Impact fits your existing org', 'Setting'],
  ['naming', 'Confirm how households are named', 'Setting'],
  ['moduledefaults', 'Choose a default contact', 'Setting'],
  ['access', 'Give your colleagues access', 'Action'],
  ['identity', "Set your organization's identity", 'Setting'],
  ['modules', 'Choose which modules to turn on', 'Action'],
  ['data', 'Bring in your data', 'Action'],
  ['verify', 'Check that everything works', 'Action']
];

// The fields each step declares, as Apex sends them: Core's own and those a module adds.
const STEP_FIELDS = {
  moduledefaults: [
    {
      fieldType: 'Record',
      key: 'Default_Contact__c',
      label: 'Default contact',
      objectApiName: 'Contact'
    },
    {
      fieldType: 'Record',
      key: 'Default_Account__c',
      label: 'Default account',
      objectApiName: 'Account'
    }
  ],
  identity: [
    { fieldType: 'Text', key: 'Organization_Legal_Name__c', label: 'Legal name', value: null }
  ],
  verify: [{ fieldType: 'Navigate', label: 'Open the module', navigationTarget: 'Module_Tab' }]
};

function steps(completedKeys = [], skippedKeys = []) {
  return STEP_DEFINITIONS.map(([key, label, rule], index) => ({
    key,
    position: index + 1,
    label,
    description: `What step ${index + 1} is for.`,
    targetType: 'Settings',
    target: 'General',
    setupPath: null,
    completionRule: rule,
    isAvailable: true,
    fields: STEP_FIELDS[key] || [],
    advanceOnSave: key === 'moduledefaults',
    skipped: skippedKeys.includes(key),
    completed: completedKeys.includes(key)
  }));
}

function state(overrides = {}) {
  const completed = overrides.completedKeys || [];
  return {
    canEdit: true,
    steps: steps(completed, overrides.skippedKeys || []),
    stepsCompleted: completed.length,
    stepsTotal: 8,
    isComplete: completed.length === 8,
    elapsedMinutes: 21,
    coexistence: {
      detectedShape: 'PersonAccounts',
      recommendedMode: 'AgentforceNonprofit',
      currentMode: null,
      modes: ['Standalone', 'NPSP', 'AgentforceNonprofit']
    },
    modules: [{ name: 'Core', present: true, docsUrl: 'https://example.invalid/core' }],
    roles: [
      { developerName: 'Nonprofit_Admin', label: 'Open Impact Admin' },
      { developerName: 'Program_Staff', label: 'Program Staff' }
    ],
    importAvailable: false,
    ...overrides
  };
}

function build(reopened = false) {
  const element = createElement('c-setup-assistant', { is: SetupAssistant });
  element.reopened = reopened;
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function click(element, id) {
  element.shadowRoot.querySelector(`[data-id="${id}"]`).click();
}

describe('c-setup-assistant', () => {
  beforeEach(() => {
    getState.mockResolvedValue(state());
    completeStep.mockResolvedValue(state({ completedKeys: ['modules'] }));
    skipStep.mockResolvedValue(state({ skippedKeys: ['moduledefaults'] }));
    applyCoexistence.mockResolvedValue(state({ completedKeys: ['coexistence'] }));
    saveStepValues.mockResolvedValue(
      state({ completedKeys: ['coexistence', 'naming', 'moduledefaults'] })
    );
    assignAccess.mockResolvedValue(state({ completedKeys: ['access'] }));
    resetSetup.mockResolvedValue(state());
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('opens one step at a time, on the first step Maria has not finished', async () => {
    getState.mockResolvedValue(state({ completedKeys: ['coexistence', 'naming'] }));
    const element = build();
    await settle();

    const label = element.shadowRoot.querySelector('[data-id="step-label"]');
    expect(label.textContent).toContain('Choose a default contact');
    expect(element.shadowRoot.querySelectorAll('[data-id="step-label"]')).toHaveLength(1);
  });

  it('walks forward and back through the steps', async () => {
    const element = build();
    await settle();

    click(element, 'forward');
    await settle();
    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      'Confirm how households are named'
    );

    click(element, 'back');
    await settle();
    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      'Confirm how Open Impact fits your existing org'
    );
  });

  it('confirms the coexistence mode through Apex and moves on', async () => {
    const element = build();
    await settle();

    element.shadowRoot
      .querySelector('c-setup-step-coexistence')
      .dispatchEvent(new CustomEvent('confirm', { detail: { mode: 'AgentforceNonprofit' } }));
    await settle();

    expect(applyCoexistence).toHaveBeenCalledWith({ mode: 'AgentforceNonprofit' });
  });

  it('skips a step without marking it done', async () => {
    const element = build();
    await settle();

    click(element, 'skip');
    await settle();

    expect(skipStep).toHaveBeenCalledWith({ stepKey: 'coexistence' });
    expect(completeStep).not.toHaveBeenCalled();
  });

  it('marks a step with no setting behind it done when Maria moves on', async () => {
    getState.mockResolvedValue(
      state({ completedKeys: ['coexistence', 'naming', 'moduledefaults'] })
    );
    const element = build();
    await settle();

    click(element, 'forward');
    await settle();

    expect(completeStep).toHaveBeenCalledWith({ stepKey: 'access' });
  });

  it('shows the fields a step declares and saves them through one method', async () => {
    getState.mockResolvedValue(state({ completedKeys: ['coexistence', 'naming'] }));
    const element = build();
    await settle();

    const panel = element.shadowRoot.querySelector('c-setup-step-fields');
    expect(panel.fields.map((field) => field.key)).toEqual([
      'Default_Contact__c',
      'Default_Account__c'
    ]);
    panel.dispatchEvent(
      new CustomEvent('save', {
        detail: { values: { Default_Contact__c: '003000000000001', Default_Account__c: null } }
      })
    );
    await settle();

    expect(saveStepValues).toHaveBeenCalledWith({
      stepKey: 'moduledefaults',
      values: { Default_Contact__c: '003000000000001', Default_Account__c: null }
    });
    // The module step asks one question, so answering it moves on.
    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      'Give your colleagues access'
    );
  });

  it('shows no field panel on a step that declares no fields', async () => {
    getState.mockResolvedValue(state({ completedKeys: ['coexistence'] }));
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-step-fields')).toBeNull();
  });

  it('gives a colleague a role from inside the assistant', async () => {
    getState.mockResolvedValue(
      state({ completedKeys: ['coexistence', 'naming', 'moduledefaults'] })
    );
    const element = build();
    await settle();

    element.shadowRoot
      .querySelector('[data-id="user-picker"]')
      .dispatchEvent(new CustomEvent('change', { detail: { recordId: '005000000000001' } }));
    element.shadowRoot
      .querySelector('lightning-combobox')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Program_Staff' } }));
    click(element, 'give-access');
    await settle();

    expect(assignAccess).toHaveBeenCalledWith({
      userId: '005000000000001',
      roleDeveloperName: 'Program_Staff'
    });
    expect(completeStep).toHaveBeenCalledWith({ stepKey: 'access' });
  });

  it('offers each role by its label, not its developer name', async () => {
    getState.mockResolvedValue(
      state({ completedKeys: ['coexistence', 'naming', 'moduledefaults'] })
    );
    const element = build();
    await settle();

    const options = element.shadowRoot.querySelector('lightning-combobox').options;
    expect(options).toEqual([
      { label: 'Open Impact Admin', value: 'Nonprofit_Admin' },
      { label: 'Program Staff', value: 'Program_Staff' }
    ]);
  });

  it('collapses back to the completion screen when a reopened setup is finished again', async () => {
    const everyStep = STEP_DEFINITIONS.map(([key]) => key);
    getState.mockResolvedValue(state({ completedKeys: everyStep }));
    completeStep.mockResolvedValue(state({ completedKeys: everyStep }));
    const element = build(true);
    await settle();

    // The Hub asked for the assistant, so it opens on step one rather than the summary.
    expect(element.shadowRoot.querySelector('[data-id="complete-heading"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      'Confirm how Open Impact fits your existing org'
    );
    await STEP_DEFINITIONS.reduce(
      (chain) =>
        chain.then(() => {
          click(element, 'forward');
          return settle();
        }),
      Promise.resolve()
    );

    expect(element.shadowRoot.querySelector('[data-id="complete-heading"]')).not.toBeNull();
  });

  it('saves the organization step and stays on it for the remaining answers', async () => {
    getState.mockResolvedValue(
      state({ completedKeys: ['coexistence', 'naming', 'moduledefaults', 'access'] })
    );
    saveStepValues.mockResolvedValue(
      state({ completedKeys: ['coexistence', 'naming', 'moduledefaults', 'access', 'identity'] })
    );
    const element = build();
    await settle();

    element.shadowRoot.querySelector('c-setup-step-fields').dispatchEvent(
      new CustomEvent('save', {
        detail: { values: { Organization_Legal_Name__c: 'Riverside Community Aid' } }
      })
    );
    await settle();

    expect(saveStepValues).toHaveBeenCalledWith({
      stepKey: 'identity',
      values: { Organization_Legal_Name__c: 'Riverside Community Aid' }
    });
    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      "Set your organization's identity"
    );
  });

  it('shows a save error on the step and stays there', async () => {
    getState.mockResolvedValue(state({ completedKeys: ['coexistence', 'naming'] }));
    saveStepValues.mockRejectedValue({ body: { message: 'That record is not a contact.' } });
    const element = build();
    await settle();

    element.shadowRoot
      .querySelector('c-setup-step-fields')
      .dispatchEvent(new CustomEvent('save', { detail: { values: { Default_Contact__c: 'x' } } }));
    await settle();

    expect(element.shadowRoot.textContent).toContain('That record is not a contact.');
    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      'Choose a default contact'
    );
  });

  it('shows the household naming panel now that C-02 ships it', async () => {
    getState.mockResolvedValue(state({ completedKeys: ['coexistence'] }));
    const element = build();
    await settle();

    // c/householdNamingSettings is in the build, so the step hosts it and the notice that
    // explains an absent panel stays hidden. The notice is what a build without C-02 shows.
    expect(element.shadowRoot.querySelector('[data-id="naming-missing"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="naming-panel"]')).not.toBeNull();
  });

  it('shows the sample data panel now that C-10 ships it', async () => {
    getState.mockResolvedValue(
      state({
        completedKeys: ['coexistence', 'naming', 'moduledefaults', 'access', 'identity', 'modules']
      })
    );
    const element = build();
    await settle();

    click(element, 'load-sample');
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="sample-missing"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="sample-panel"]')).not.toBeNull();
  });

  it('shows the button a module adds to the last step', async () => {
    getState.mockResolvedValue(
      state({
        completedKeys: [
          'coexistence',
          'naming',
          'moduledefaults',
          'access',
          'identity',
          'modules',
          'data'
        ]
      })
    );
    const element = build();
    await settle();

    const panel = element.shadowRoot.querySelector('c-setup-step-fields');
    expect(panel.fields[0].navigationTarget).toBe('Module_Tab');
  });

  it('opens on a step Maria skipped the next time she comes back', async () => {
    getState.mockResolvedValue(
      state({ completedKeys: ['coexistence', 'naming'], skippedKeys: ['moduledefaults'] })
    );
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      'Choose a default contact'
    );
  });

  it('opens on the first step when the Hub asked to reopen a finished setup', async () => {
    getState.mockResolvedValue(state({ completedKeys: STEP_DEFINITIONS.map(([key]) => key) }));
    const element = build(true);
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="complete-heading"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      'Confirm how Open Impact fits your existing org'
    );
  });

  it('confirms that a colleague was given a role', async () => {
    getState.mockResolvedValue(
      state({ completedKeys: ['coexistence', 'naming', 'moduledefaults'] })
    );
    const element = build();
    await settle();

    element.shadowRoot
      .querySelector('[data-id="user-picker"]')
      .dispatchEvent(new CustomEvent('change', { detail: { recordId: '005000000000001' } }));
    element.shadowRoot
      .querySelector('lightning-combobox')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Program_Staff' } }));
    const picker = element.shadowRoot.querySelector('[data-id="user-picker"]');
    picker.clearSelection = jest.fn();
    click(element, 'give-access');
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="access-granted"]')).not.toBeNull();
    expect(picker.clearSelection).toHaveBeenCalled();
  });

  it('shows the summary and how long setup took once every step is done', async () => {
    getState.mockResolvedValue(state({ completedKeys: STEP_DEFINITIONS.map(([key]) => key) }));
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="complete-heading"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="elapsed"]').textContent).toContain('21');
    expect(element.shadowRoot.querySelectorAll('li')).toHaveLength(8);

    click(element, 'reopen');
    await settle();
    expect(element.shadowRoot.querySelector('[data-id="step-label"]')).not.toBeNull();
  });

  it('starts setup again when Maria asks, and forgets the progress it recorded', async () => {
    getState.mockResolvedValue(state({ completedKeys: STEP_DEFINITIONS.map(([key]) => key) }));
    const element = build();
    await settle();

    click(element, 'start-again');
    await settle();

    expect(resetSetup).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="step-label"]').textContent).toContain(
      'Confirm how Open Impact fits your existing org'
    );
  });

  it('tells the page how far setup has got', async () => {
    const element = build();
    const changed = jest.fn();
    element.addEventListener('setupchanged', changed);
    await settle();

    expect(changed).toHaveBeenCalled();
    expect(changed.mock.calls[0][0].detail.stepsTotal).toBe(8);
  });

  it('tells David he may read the steps but not change them', async () => {
    getState.mockResolvedValue(state({ canEdit: false }));
    const element = build();
    await settle();

    expect(element.shadowRoot.textContent).toContain('Core_SetupAssistant_ReadOnlyNotice');
  });

  it('shows a message Maria can act on when the assistant cannot be loaded', async () => {
    getState.mockRejectedValue({ body: { message: 'No luck today.' } });
    const element = build();
    await settle();

    expect(element.shadowRoot.textContent).toContain('No luck today.');
  });
});
