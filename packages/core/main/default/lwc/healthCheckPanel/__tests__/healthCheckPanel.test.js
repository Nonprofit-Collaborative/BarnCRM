import { createElement } from 'lwc';
import HealthCheckPanel from 'c/healthCheckPanel';
import getReport from '@salesforce/apex/HealthCheckController.getReport';
import applyRecommendedMode from '@salesforce/apex/HealthCheckController.applyRecommendedMode';
import applyJunctionMembership from '@salesforce/apex/HealthCheckController.applyJunctionMembership';
import enableAutomaticHouseholds from '@salesforce/apex/HealthCheckController.enableAutomaticHouseholds';
import applyFix from '@salesforce/apex/HealthCheckController.applyFix';

jest.mock('@salesforce/apex/HealthCheckController.getReport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/HealthCheckController.applyRecommendedMode',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HealthCheckController.applyJunctionMembership',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HealthCheckController.enableAutomaticHouseholds',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/HealthCheckController.applyFix', () => ({ default: jest.fn() }), {
  virtual: true
});

const mockNavigate = jest.fn();
// Not virtual: sfdx-lwc-jest resolves this module to a stub file, and a virtual mock of a
// resolvable module is matched to the component's import unreliably in a parallel run, so the
// component sometimes got the stub instead of the mock.
jest.mock('lightning/navigation', () => {
  const Navigate = Symbol('Navigate');
  const GenerateUrl = Symbol('GenerateUrl');
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](...args) {
        mockNavigate(...args);
      }
      [GenerateUrl]() {
        return Promise.resolve('https://example.com');
      }
    };
  NavigationMixin.Navigate = Navigate;
  NavigationMixin.GenerateUrl = GenerateUrl;
  return { NavigationMixin, CurrentPageReference: null, __esModule: true };
});

/** Maria's org: Person Accounts on, Nonprofit Cloud objects present, no mode confirmed. */
function agentforceReport(overrides = {}) {
  return {
    canManageSettings: true,
    modeNeedsAttention: true,
    currentModeLabel: 'not confirmed yet',
    recommendedModeLabel: 'Agentforce Nonprofit coexistence',
    orgShapeSummary: 'Person Accounts enabled. Agentforce Nonprofit objects detected.',
    orgShape: { hasPersonAccounts: true, hasIndustriesNonprofit: true },
    // Both come from Apex, which computes them from the running namespace. Unmanaged, which
    // is what the scratch orgs are, they look like this.
    settingsTabApiName: 'Nonprofit_Settings',
    sectionStateKey: 'c__section',
    findings: [
      {
        key: 'org_shape',
        title: 'What we found in your org',
        detail: 'Person Accounts enabled.',
        severity: 'Info',
        category: 'OrgShape',
        fixLabel: null,
        fixTarget: null
      },
      {
        key: 'membership_mode_person_accounts',
        title: 'Household membership does not fit Person Accounts',
        detail: 'Person Accounts are enabled.',
        severity: 'Error',
        category: 'OrgShape',
        fixLabel: 'Switch to junction membership',
        fixTarget: 'action:applyJunctionMembership'
      },
      {
        key: 'household_creation_disabled',
        title: 'No new person is getting a household',
        detail: 'Household membership uses membership records and automatic creation is off.',
        severity: 'Error',
        category: 'Settings',
        fixLabel: 'Turn on automatic households',
        fixTarget: 'action:enableAutomaticHouseholds'
      },
      {
        key: 'no_nonprofit_admin',
        title: 'No one is assigned the Nonprofit Admin role',
        detail: 'Nobody has the role.',
        severity: 'Error',
        category: 'Access',
        fixLabel: 'Open the Access page',
        fixTarget: 'Access'
      },
      {
        key: 'shipped_rollups_missing',
        title: '2 shipped rollups are missing',
        detail: 'Open Impact ships totals this org does not have: Total Gifts, Last Gift Date.',
        severity: 'Warning',
        category: 'Settings',
        fixLabel: 'Restore shipped rollups',
        fixTarget: 'action:restoreShippedRollups',
        fixScope: ['Total Gifts', 'Last Gift Date']
      },
      {
        key: 'error_log_new',
        title: '2 errors nobody has looked at',
        detail: 'The Error Log has 2 new entries.',
        severity: 'Warning',
        category: 'Settings',
        fixLabel: 'Open the Error Log',
        fixTarget: '/lightning/o/Error_Log__c/list'
      }
    ],
    ...overrides
  };
}

function createPanel() {
  const element = createElement('c-health-check-panel', { is: HealthCheckPanel });
  document.body.appendChild(element);
  return element;
}

function clickSectionFix(element) {
  const fixes = element.shadowRoot.querySelectorAll('[data-id="fix"]');
  Array.from(fixes)
    .find((button) => button.dataset.target === 'Access')
    .click();
}

function clickFix(element, target) {
  const fixes = element.shadowRoot.querySelectorAll('[data-id="fix"]');
  Array.from(fixes)
    .find((button) => button.dataset.target === target)
    .click();
}

function confirmBox(element) {
  return element.shadowRoot.querySelector('[data-id="confirm"]');
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-health-check-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    mockNavigate.mockClear();
  });

  it('shows the org shape card and every finding, grouped', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    const summary = element.shadowRoot.querySelector('[data-id="org-shape-summary"]');
    expect(summary.textContent).toContain('Person Accounts enabled');

    const findings = element.shadowRoot.querySelectorAll('[data-id="finding"]');
    expect(findings.length).toBe(6);

    const groups = element.shadowRoot.querySelectorAll('[data-id="group"]');
    expect(groups.length).toBe(3);
  });

  it('offers the recommended mode when the mode needs attention', async () => {
    getReport.mockResolvedValue(agentforceReport());
    applyRecommendedMode.mockResolvedValue(
      agentforceReport({ modeNeedsAttention: false, findings: [] })
    );
    const element = createPanel();
    await flush();

    const button = element.shadowRoot.querySelector('[data-id="use-recommended"]');
    expect(button).not.toBeNull();
    button.click();
    await flush();

    expect(applyRecommendedMode).not.toHaveBeenCalled();
    expect(confirmBox(element)).not.toBeNull();
    element.shadowRoot.querySelector('[data-id="confirm-run"]').click();
    await flush();

    expect(applyRecommendedMode).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="use-recommended"]')).toBeNull();
  });

  it('runs the junction membership fix from the finding', async () => {
    getReport.mockResolvedValue(agentforceReport());
    applyJunctionMembership.mockResolvedValue(agentforceReport({ findings: [] }));
    const element = createPanel();
    await flush();

    clickFix(element, 'action:applyJunctionMembership');
    await flush();
    expect(applyJunctionMembership).not.toHaveBeenCalled();

    element.shadowRoot.querySelector('[data-id="confirm-run"]').click();
    await flush();

    expect(applyJunctionMembership).toHaveBeenCalled();
  });

  it('runs the automatic households fix from the finding', async () => {
    getReport.mockResolvedValue(agentforceReport());
    enableAutomaticHouseholds.mockResolvedValue(agentforceReport({ findings: [] }));
    const element = createPanel();
    await flush();

    clickFix(element, 'action:enableAutomaticHouseholds');
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-run"]').click();
    await flush();

    expect(enableAutomaticHouseholds).toHaveBeenCalled();
  });

  it('shows what a fix will do and runs nothing until it is confirmed', async () => {
    getReport.mockResolvedValue(agentforceReport());
    applyFix.mockResolvedValue(agentforceReport({ findings: [] }));
    const element = createPanel();
    await flush();

    clickFix(element, 'action:restoreShippedRollups');
    await flush();

    expect(applyFix).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="confirm-title"]').textContent).toContain(
      '2 shipped rollups are missing'
    );
    expect(element.shadowRoot.querySelector('[data-id="confirm-detail"]').textContent).toContain(
      'Total Gifts, Last Gift Date'
    );

    element.shadowRoot.querySelector('[data-id="confirm-run"]').click();
    await flush();

    expect(applyFix).toHaveBeenCalledWith({
      fixKey: 'restoreShippedRollups',
      expectedScope: ['Total Gifts', 'Last Gift Date']
    });
    expect(confirmBox(element)).toBeNull();
  });

  it('says what the fix did once it has run', async () => {
    getReport.mockResolvedValue(agentforceReport());
    applyFix.mockResolvedValue(
      agentforceReport({ findings: [], fixOutcome: 'Done. Created: Total Gifts, Last Gift Date.' })
    );
    const element = createPanel();
    await flush();

    clickFix(element, 'action:restoreShippedRollups');
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-run"]').click();
    await flush();

    const outcome = element.shadowRoot.querySelector('[data-id="fix-outcome"]');
    expect(outcome.textContent).toContain('Created: Total Gifts, Last Gift Date');
  });

  it('moves focus into the confirm box and scrolls it into view', async () => {
    const scrollIntoView = jest.fn();
    Element.prototype.scrollIntoView = scrollIntoView;
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    clickFix(element, 'action:restoreShippedRollups');
    await flush();

    const dialog = confirmBox(element);
    expect(dialog.getAttribute('role')).toBe('dialog');
    expect(element.shadowRoot.activeElement).toBe(dialog);
    expect(scrollIntoView).toHaveBeenCalled();
    delete Element.prototype.scrollIntoView;
  });

  it('closes on Escape and returns focus to the button that opened it', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    const fixButton = Array.from(element.shadowRoot.querySelectorAll('[data-id="fix"]')).find(
      (button) => button.dataset.target === 'action:restoreShippedRollups'
    );
    const focus = jest.spyOn(fixButton, 'focus');
    fixButton.click();
    await flush();

    confirmBox(element).dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await flush();

    expect(confirmBox(element)).toBeNull();
    expect(focus).toHaveBeenCalled();
    expect(applyFix).not.toHaveBeenCalled();
  });

  it('opens no confirm box for a finding with nothing to show, and runs Health Check again', async () => {
    getReport.mockResolvedValue(
      agentforceReport({
        findings: [
          {
            key: 'import_templates_missing',
            title: '',
            detail: '',
            severity: 'Info',
            category: 'Settings',
            fixLabel: 'Restore import templates',
            fixTarget: 'action:restoreImportTemplates',
            fixScope: ['Generic donor list']
          }
        ]
      })
    );
    const element = createPanel();
    await flush();

    clickFix(element, 'action:restoreImportTemplates');
    await flush();

    expect(confirmBox(element)).toBeNull();
    expect(getReport).toHaveBeenCalledTimes(2);
    expect(applyFix).not.toHaveBeenCalled();
  });

  it('runs nothing when the fix is cancelled', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    clickFix(element, 'action:restoreShippedRollups');
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-cancel"]').click();
    await flush();

    expect(confirmBox(element)).toBeNull();
    expect(applyFix).not.toHaveBeenCalled();
  });

  it('shows the message when a confirmed fix fails', async () => {
    getReport.mockResolvedValue(agentforceReport());
    applyFix.mockRejectedValue({
      body: { message: 'That did not work, and nothing was changed.' }
    });
    const element = createPanel();
    await flush();

    clickFix(element, 'action:restoreShippedRollups');
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-run"]').click();
    await flush();
    await flush();

    const error = element.shadowRoot.querySelector('[data-id="error"]');
    expect(error.textContent).toBe('That did not work, and nothing was changed.');
    expect(getReport).toHaveBeenCalledTimes(2);
  });

  it('links the records an orphan finding names, with no fix button', async () => {
    getReport.mockResolvedValue(
      agentforceReport({
        findings: [
          {
            key: 'people_without_household',
            title: '2 people are not in a household',
            detail: 'These contacts have no account. The first 2 are linked below.',
            severity: 'Warning',
            category: 'Settings',
            fixLabel: null,
            fixTarget: null,
            links: [
              { label: 'Ann Lee', url: '/lightning/r/Contact/003000000000001AAA/view' },
              { label: 'Bo Diaz', url: '/lightning/r/Contact/003000000000002AAA/view' }
            ]
          }
        ]
      })
    );
    const element = createPanel();
    await flush();

    const links = element.shadowRoot.querySelectorAll('[data-id="finding-link"]');
    expect(links.length).toBe(2);
    expect(links[0].textContent).toBe('Ann Lee');
    expect(links[0].getAttribute('href')).toBe('/lightning/r/Contact/003000000000001AAA/view');
    expect(element.shadowRoot.querySelector('[data-id="fix"]')).toBeNull();
  });

  it('navigates to a relative URL fix', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    const fixes = element.shadowRoot.querySelectorAll('[data-id="fix"]');
    const errorLog = Array.from(fixes).find((button) => button.dataset.target.startsWith('/'));
    errorLog.click();
    await flush();

    expect(confirmBox(element)).toBeNull();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__webPage',
      attributes: { url: '/lightning/o/Error_Log__c/list' }
    });
  });

  it('navigates to the settings console when no host handles the section fix', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    const handler = jest.fn();
    element.addEventListener('navigatetosection', handler);
    await flush();

    clickSectionFix(element);
    await flush();

    expect(handler).toHaveBeenCalled();
    expect(handler.mock.calls[0][0].detail.section).toBe('Access');
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Nonprofit_Settings' },
      state: { c__section: 'Access' }
    });
  });

  it('leaves the section fix to a host that handles it, and does not also navigate', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    const handler = jest.fn((event) => event.preventDefault());
    element.addEventListener('navigatetosection', handler);
    await flush();

    clickSectionFix(element);
    await flush();

    expect(handler).toHaveBeenCalled();
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('uses the namespaced tab and state key the report supplies', async () => {
    getReport.mockResolvedValue(
      agentforceReport({
        settingsTabApiName: 'example__Nonprofit_Settings',
        sectionStateKey: 'example__section'
      })
    );
    const element = createPanel();
    await flush();

    clickSectionFix(element);
    await flush();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'example__Nonprofit_Settings' },
      state: { example__section: 'Access' }
    });
  });

  it('is read only without the permission', async () => {
    getReport.mockResolvedValue(agentforceReport({ canManageSettings: false }));
    const element = createPanel();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="read-only"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="fix"]').length).toBe(0);
    expect(element.shadowRoot.querySelector('[data-id="use-recommended"]')).toBeNull();
  });

  it('re-runs on demand', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    element.shadowRoot.querySelector('[data-id="rerun"]').click();
    await flush();

    expect(getReport).toHaveBeenCalledTimes(2);
  });

  it('shows the message when the report cannot be read', async () => {
    getReport.mockRejectedValue({ body: { message: 'Health Check could not read your org.' } });
    const element = createPanel();
    await flush();

    const error = element.shadowRoot.querySelector('[data-id="error"]');
    expect(error.textContent).toBe('Health Check could not read your org.');
  });
});
