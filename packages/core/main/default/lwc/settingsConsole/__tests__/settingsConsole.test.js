import { createElement } from 'lwc';
import SettingsConsole from 'c/settingsConsole';
import FeatureSettings from 'c/featureSettings';
import getConsoleModel from '@salesforce/apex/SettingsController.getConsoleModel';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import getRecentChanges from '@salesforce/apex/SettingsController.getRecentChanges';
import * as navigation from 'lightning/navigation';
import { EnclosingTabId, setTabIcon, setTabLabel } from 'lightning/platformWorkspaceApi';

jest.mock('@salesforce/label/c.Core_Console_TabLabel', () => ({ default: '{0}: {1}' }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Core_Settings_FeedbackLink',
  () => ({ default: 'Report a problem or give feedback' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_Settings_FeedbackAria',
  () => ({ default: 'Report a problem or give feedback (opens a new tab)' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_Settings_FeedbackUrl',
  () => ({ default: 'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/SUPPORT.md' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_Settings_LearnMoreAria',
  () => ({ default: 'Learn more about {0} (opens a new tab)' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_Settings_OpenSectionButton',
  () => ({ default: 'Open this page' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Core_Settings_OpenNamedButton', () => ({ default: 'Open {0}' }), {
  virtual: true
});

jest.mock('@salesforce/apex/SettingsController.getConsoleModel', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SettingsController.saveSettings', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SettingsController.getRecentChanges', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SettingsController.search', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/SettingsController.getSetupChecks',
  () => ({ default: jest.fn().mockResolvedValue({}) }),
  { virtual: true }
);
// The naming panel is replaced by a stub so these tests see only the console's own work.
jest.mock('c/householdNamingSettings', () =>
  require('../../../../../test/jest-mocks/settingsConsole/householdNamingSettings')
);
jest.mock('c/featureSettings', () =>
  require('../../../../../test/jest-mocks/settingsConsole/featureSettings')
);

const NAMING_KEYS = [
  'Household_Name_Pattern__c',
  'Formal_Greeting_Pattern__c',
  'Informal_Greeting_Pattern__c'
];

/** A Households section as the package ships it: three pattern rows, a checkbox, the panel. */
function householdsWithPanelModel() {
  const text = (key, label) => ({
    key,
    label,
    description: null,
    dataType: 'Text',
    section: 'Households',
    component: null,
    helpUrl: null,
    value: 'x',
    checked: false,
    options: []
  });
  return {
    canEdit: true,
    sections: [
      {
        name: 'Households',
        settings: [
          text('Household_Name_Pattern__c', 'Household name pattern'),
          text('Formal_Greeting_Pattern__c', 'Formal greeting pattern'),
          text('Informal_Greeting_Pattern__c', 'Informal greeting pattern'),
          {
            key: 'Include_Deceased_In_Name__c',
            label: 'Include deceased in name',
            description: null,
            dataType: 'Checkbox',
            section: 'Households',
            component: null,
            helpUrl: null,
            value: 'false',
            checked: false,
            options: []
          },
          {
            key: 'Household_Naming_Preview',
            label: 'Preview and recompute',
            description: null,
            dataType: 'Component',
            section: 'Households',
            settingsObject: 'BarnCRM_Settings__c',
            component: 'householdNamingSettings',
            navigationTarget: null,
            helpUrl: null,
            value: null,
            checked: false,
            options: []
          }
        ]
      }
    ]
  };
}

// Reached through the module namespace rather than by name: a wire adapter may only be named
// in a @wire decorator, and a test drives it through the stub's emit.
function openSection(name, key = 'c__section') {
  navigation.CurrentPageReference.emit({ state: { [key]: name } });
}

function model(canEdit) {
  return {
    canEdit,
    sections: [
      {
        name: 'Households',
        settings: [
          {
            key: 'Household_Name_Pattern__c',
            label: 'Household name pattern',
            description: 'How a household name is built.',
            dataType: 'Text',
            section: 'Households',
            component: null,
            helpUrl: 'https://example.invalid/docs/household-naming.md',
            value: 'The {LastName} Family',
            checked: false,
            options: []
          },
          {
            key: 'Auto_Create_Households__c',
            label: 'Create households automatically',
            description: 'Whether adding a person creates a household.',
            dataType: 'Checkbox',
            section: 'Households',
            component: null,
            helpUrl: null,
            value: 'true',
            checked: true,
            options: []
          },
          {
            key: 'Import_Chunk_Size__c',
            label: 'Rows per import chunk',
            description: 'How many rows an import processes at a time.',
            dataType: 'Number',
            section: 'Households',
            component: null,
            helpUrl: null,
            value: '200',
            checked: false,
            options: [],
            minValue: 1,
            maxValue: 2000
          }
        ]
      },
      {
        name: 'General',
        settings: [
          {
            key: 'Coexistence_Mode__c',
            label: 'How BarnCRM fits your org',
            description: 'Set after BarnCRM looks at your org.',
            dataType: 'Picklist',
            section: 'General',
            component: null,
            helpUrl: null,
            value: 'Standalone',
            checked: false,
            options: [
              { label: 'On its own', value: 'Standalone' },
              { label: 'Alongside Nonprofit Cloud', value: 'NonprofitCloud' }
            ]
          }
        ]
      },
      {
        name: 'Giving',
        settings: [
          {
            key: 'Giving_Settings_Page',
            label: 'Gift entry and receipts',
            description: 'The Giving module keeps its settings on its own page.',
            dataType: 'Component',
            section: 'Giving',
            settingsObject: 'Giving_Settings__c',
            component: null,
            navigationTarget: 'Giving_Settings',
            helpUrl: null,
            value: null,
            checked: false,
            options: []
          }
        ]
      },
      {
        name: 'Defaults',
        settings: [
          {
            key: 'Default_Fund__c',
            label: 'Default fund',
            description: 'The fund a gift goes to when nobody chooses one.',
            dataType: 'Record',
            section: 'Defaults',
            objectApiName: 'Fund__c',
            component: null,
            helpUrl: null,
            value: 'a01000000000001AAA',
            checked: false,
            options: []
          },
          {
            key: 'Program_Record_Types__c',
            label: 'Program record types',
            description: 'Which kinds of program count.',
            dataType: 'RecordTypeList',
            section: 'Defaults',
            objectApiName: 'Program__c',
            component: null,
            helpUrl: null,
            value: 'Donation',
            checked: false,
            options: [
              { label: 'Donation', value: 'Donation' },
              { label: 'Major Gift', value: 'Major_Gift' }
            ]
          }
        ]
      },
      {
        name: 'Health',
        settings: [
          {
            key: 'Health_Check_Panel',
            label: 'Health check',
            description: 'What BarnCRM found in your org.',
            dataType: 'Component',
            section: 'Health',
            settingsObject: 'BarnCRM_Settings__c',
            component: 'notAComponentInThisBuild',
            navigationTarget: null,
            helpUrl: null,
            value: null,
            checked: false,
            options: []
          }
        ]
      }
    ]
  };
}

function build() {
  const element = createElement('c-settings-console', { is: SettingsConsole });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-settings-console', () => {
  beforeEach(() => {
    getConsoleModel.mockResolvedValue(model(true));
    saveSettings.mockResolvedValue(model(true));
    getRecentChanges.mockResolvedValue([]);
  });

  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the first section with its controls and help', async () => {
    const element = build();
    await settle();

    const navItems = element.shadowRoot.querySelectorAll('lightning-vertical-navigation-item');
    expect(navItems).toHaveLength(5);

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(inputs).toHaveLength(3);
    expect(inputs[0].value).toBe('The {LastName} Family');
    expect(inputs[1].checked).toBe(true);

    const help = element.shadowRoot.querySelector('a[target="_blank"]');
    expect(help).not.toBeNull();
    expect(help.href).toContain('household-naming.md');
    expect(help.getAttribute('aria-label')).toBe(
      'Learn more about Household name pattern (opens a new tab)'
    );
  });

  describe('Recent Changes', () => {
    const change = {
      id: 'a01',
      settingName: 'Fiscal year start month',
      oldValue: '1',
      newValue: '7',
      changedBy: 'Maria',
      changedAt: '2026-10-01T12:00:00.000Z'
    };

    function recentBlock(element) {
      return (
        Array.from(element.shadowRoot.querySelectorAll('h2')).find((heading) =>
          heading.textContent.includes('Core_Settings_RecentChangesHeading')
        ) || null
      );
    }

    beforeEach(() => {
      getRecentChanges.mockResolvedValue([change]);
    });

    it('shows on the General section', async () => {
      const element = build();
      await settle();
      openSection('General');
      await settle();

      expect(recentBlock(element)).not.toBeNull();
      expect(element.shadowRoot.querySelector('lightning-datatable')).not.toBeNull();
    });

    it('does not show on any other section', async () => {
      const element = build();
      await settle();

      // The console opens on the first section, which is not General.
      expect(recentBlock(element)).toBeNull();
      expect(element.shadowRoot.querySelector('lightning-datatable')).toBeNull();

      openSection('General');
      await settle();
      expect(recentBlock(element)).not.toBeNull();

      openSection('Households');
      await settle();
      expect(recentBlock(element)).toBeNull();
    });

    it('does not show when a search result jumps to another section', async () => {
      const element = build();
      await settle();
      openSection('General');
      await settle();

      element.shadowRoot.querySelector('c-settings-search').dispatchEvent(
        new CustomEvent('settingselect', {
          detail: { section: 'Households', key: 'Include_Deceased_In_Name__c' }
        })
      );
      await settle();

      expect(recentBlock(element)).toBeNull();
    });
  });

  it('links to the feedback page in a new tab', async () => {
    const element = build();
    await settle();

    const link = [...element.shadowRoot.querySelectorAll('a')].find(
      (a) => a.textContent.trim() === 'Report a problem or give feedback'
    );
    expect(link).toBeTruthy();
    expect(link.getAttribute('href')).toBe(
      'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/SUPPORT.md'
    );
    expect(link.getAttribute('target')).toBe('_blank');
    expect(link.getAttribute('rel')).toContain('noopener');
    expect(link.getAttribute('aria-label')).toBe(
      'Report a problem or give feedback (opens a new tab)'
    );
  });

  it('sends only the settings Maria changed', async () => {
    const element = build();
    await settle();

    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = 'The {LastName} Household';
    input.dispatchEvent(new CustomEvent('change'));
    await settle();

    const buttons = element.shadowRoot.querySelectorAll('lightning-button');
    buttons[0].click();
    await settle();

    expect(saveSettings).toHaveBeenCalledWith({
      values: { Household_Name_Pattern__c: 'The {LastName} Household' }
    });
    expect(element.shadowRoot.querySelector('p[role="status"]')).not.toBeNull();
  });

  it('throws away unsaved edits when Maria discards them', async () => {
    const element = build();
    await settle();

    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = 'Something else';
    input.dispatchEvent(new CustomEvent('change'));
    await settle();

    const buttons = element.shadowRoot.querySelectorAll('lightning-button');
    buttons[1].click();
    await settle();

    expect(saveSettings).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('lightning-input').value).toBe('The {LastName} Family');
  });

  it('tells David which permission he needs and offers him no Save button', async () => {
    getConsoleModel.mockResolvedValue(model(false));
    const element = build();
    await settle();

    const notice = element.shadowRoot.querySelector('div[role="status"]');
    expect(notice.textContent).toContain('Core_Settings_ReadOnlyNotice');
    expect(element.shadowRoot.querySelectorAll('lightning-button')).toHaveLength(0);
    element.shadowRoot.querySelectorAll('lightning-input').forEach((input) => {
      expect(input.disabled).toBe(true);
    });
  });

  it('opens the section a search result points at', async () => {
    const element = build();
    await settle();

    const search = element.shadowRoot.querySelector('c-settings-search');
    search.dispatchEvent(
      new CustomEvent('settingselect', {
        detail: { section: 'General', key: 'Coexistence_Mode__c' }
      })
    );
    await settle();

    const combobox = element.shadowRoot.querySelector('lightning-combobox');
    expect(combobox).not.toBeNull();
    expect(combobox.value).toBe('Standalone');
  });

  it('leaves the tab alone outside a console', async () => {
    build();
    await settle();

    expect(setTabLabel).not.toHaveBeenCalled();
    expect(setTabIcon).not.toHaveBeenCalled();
  });

  it('names the console tab for the section on screen', async () => {
    const element = build();
    EnclosingTabId.emit('tab0');
    await settle();

    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_Settings_Title: Households');
    expect(setTabIcon).toHaveBeenCalledWith('tab0', 'standard:settings', {
      iconAlt: 'c.Core_Settings_Title: Households'
    });

    element.shadowRoot
      .querySelector('c-settings-search')
      .dispatchEvent(new CustomEvent('settingselect', { detail: { section: 'General' } }));
    await settle();

    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_Settings_Title: General');
  });

  it('scrolls to and focuses the setting a search result names', async () => {
    const element = build();
    await settle();
    const focus = jest.fn();
    const scrollIntoView = jest.fn();
    const originalFocus = HTMLElement.prototype.focus;
    const originalScroll = HTMLElement.prototype.scrollIntoView;
    HTMLElement.prototype.focus = focus;
    HTMLElement.prototype.scrollIntoView = scrollIntoView;
    try {
      const search = element.shadowRoot.querySelector('c-settings-search');
      search.dispatchEvent(
        new CustomEvent('settingselect', {
          detail: { section: 'General', key: 'Coexistence_Mode__c' }
        })
      );
      await settle();
    } finally {
      HTMLElement.prototype.focus = originalFocus;
      HTMLElement.prototype.scrollIntoView = originalScroll;
    }

    expect(scrollIntoView).toHaveBeenCalledTimes(1);
    expect(focus).toHaveBeenCalledTimes(1);
    expect(focus.mock.instances[0].dataset.key).toBe('Coexistence_Mode__c');
  });

  it('opens the section a setup step asked for', async () => {
    const element = build();
    openSection('General');
    await settle();

    const combobox = element.shadowRoot.querySelector('lightning-combobox');
    expect(combobox).not.toBeNull();
    expect(combobox.value).toBe('Standalone');
  });

  it('opens the section a namespaced link asked for', async () => {
    const element = build();
    openSection('General', 'barn__section');
    await settle();

    const combobox = element.shadowRoot.querySelector('lightning-combobox');
    expect(combobox).not.toBeNull();
    expect(combobox.value).toBe('Standalone');
  });

  it('puts the Setup note of the open section at the top of it', async () => {
    const element = build();
    await settle();

    const notes = element.shadowRoot.querySelector('c-settings-setup-notes');
    expect(notes.section).toBe('Households');

    openSection('General');
    await settle();
    expect(notes.section).toBe('General');
  });

  it("shows only a module's rows, and no search, on that module's own page", async () => {
    const row = (key, section, module) => ({
      key,
      label: key,
      description: null,
      dataType: 'Text',
      section,
      module,
      component: null,
      helpUrl: null,
      value: 'x',
      checked: false,
      options: []
    });
    getConsoleModel.mockResolvedValue({
      canEdit: true,
      sections: [
        { name: 'General', settings: [row('Fiscal_Year_Start_Month__c', 'General', 'Core')] },
        {
          name: 'Rollups',
          settings: [
            row('Rollup_Mode_Default__c', 'Rollups', 'Rollups'),
            row('Rollup_Processing__c', 'Rollups', 'Rollups')
          ]
        }
      ]
    });
    const element = createElement('c-settings-console', { is: SettingsConsole });
    element.module = 'Rollups';
    document.body.appendChild(element);
    await settle();

    const navItems = element.shadowRoot.querySelectorAll('lightning-vertical-navigation-item');
    expect(navItems).toHaveLength(1);
    expect(navItems[0].name).toBe('Rollups');
    expect(element.shadowRoot.querySelectorAll('lightning-input')).toHaveLength(2);
    expect(element.shadowRoot.querySelector('c-settings-search')).toBeNull();
  });

  it('offers a module its own page instead of trying to render it', async () => {
    const element = build();
    openSection('Giving');
    await settle();

    const button = element.shadowRoot.querySelector('lightning-button[data-target]');
    expect(button).not.toBeNull();
    expect(button.dataset.target).toBe('Giving_Settings');
    expect(button.label).toBe('Open this page');
  });

  it('names the page its button opens when the row says what it is called', async () => {
    const named = model(true);
    named.sections.find((s) => s.name === 'Giving').settings[0].navigationLabel = 'Rollup Builder';
    getConsoleModel.mockResolvedValue(named);
    const element = build();
    openSection('Giving');
    await settle();

    const button = element.shadowRoot.querySelector('lightning-button[data-target]');
    expect(button.label).toBe('Open Rollup Builder');
  });

  it('says so plainly when the module that brings a panel is not installed', async () => {
    const element = build();
    openSection('Health');
    await settle();

    const notice = element.shadowRoot.querySelector('p[role="status"]');
    expect(notice.textContent).toContain('Core_Settings_ComponentNotInstalled');
  });

  it('ties each description to its setting for a screen reader', async () => {
    const element = build();
    await settle();

    const groups = element.shadowRoot.querySelectorAll('div[role="group"]');
    expect(groups).toHaveLength(3);
    const describedBy = groups[0].getAttribute('aria-describedby');
    expect(describedBy).toBeTruthy();
    const description = element.shadowRoot.querySelector(`[id="${describedBy}"]`);
    expect(description.textContent).toContain('How a household name is built.');
    expect(groups[0].getAttribute('aria-label')).toBe('Household name pattern');
  });

  it('lets Maria pick a record and tick record types instead of typing identifiers', async () => {
    const element = build();
    openSection('Defaults');
    await settle();

    expect(element.shadowRoot.querySelectorAll('lightning-input')).toHaveLength(0);
    const picker = element.shadowRoot.querySelector('lightning-record-picker');
    expect(picker.objectApiName).toBe('Fund__c');
    expect(picker.value).toBe('a01000000000001AAA');
    const boxes = element.shadowRoot.querySelector('lightning-checkbox-group');
    expect(boxes.value).toEqual(['Donation']);
    expect(boxes.options).toHaveLength(2);

    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: 'a01000000000002AAA' } }));
    boxes.dispatchEvent(
      new CustomEvent('change', { detail: { value: ['Donation', 'Major_Gift'] } })
    );
    await settle();
    element.shadowRoot.querySelectorAll('lightning-button')[0].click();
    await settle();

    expect(saveSettings).toHaveBeenCalledWith({
      values: {
        Default_Fund__c: 'a01000000000002AAA',
        Program_Record_Types__c: 'Donation,Major_Gift'
      }
    });
  });

  it('clears a picked record and unticks every record type to empty', async () => {
    const element = build();
    openSection('Defaults');
    await settle();

    element.shadowRoot
      .querySelector('lightning-record-picker')
      .dispatchEvent(new CustomEvent('change', { detail: { recordId: null } }));
    element.shadowRoot
      .querySelector('lightning-checkbox-group')
      .dispatchEvent(new CustomEvent('change', { detail: { value: [] } }));
    await settle();

    expect(element.shadowRoot.querySelector('lightning-checkbox-group').value).toEqual([]);
    element.shadowRoot.querySelectorAll('lightning-button')[0].click();
    await settle();

    expect(saveSettings).toHaveBeenCalledWith({
      values: { Default_Fund__c: '', Program_Record_Types__c: '' }
    });
  });

  it('says the page could not load rather than showing nothing', async () => {
    getConsoleModel.mockRejectedValue(new Error('no'));
    const element = build();
    await settle();

    const message = element.shadowRoot.querySelector('p[role="status"]');
    expect(message.textContent).toContain('Core_Settings_LoadErrorMessage');
  });

  it('gives a number its range, and sends nothing while a number is outside it (ADMIN-27)', async () => {
    const element = build();
    await settle();

    const input = element.shadowRoot.querySelector('lightning-input[data-kind="Number"]');
    expect(input.min).toBe(1);
    expect(input.max).toBe(2000);

    input.value = '5000';
    input.dispatchEvent(new CustomEvent('change'));
    input.reportValidity = jest.fn(() => false);
    await settle();

    element.shadowRoot.querySelectorAll('lightning-button')[0].click();
    await settle();

    expect(input.reportValidity).toHaveBeenCalled();
    expect(saveSettings).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('p[role="status"]').textContent).toContain(
      'Core_Settings_NumberOutOfRangeOnPage'
    );

    input.reportValidity = jest.fn(() => true);
    element.shadowRoot.querySelectorAll('lightning-button')[0].click();
    await settle();

    expect(saveSettings).toHaveBeenCalledWith({ values: { Import_Chunk_Size__c: '5000' } });
  });

  describe('Households naming patterns (ADMIN-11)', () => {
    beforeEach(() => {
      getConsoleModel.mockResolvedValue(householdsWithPanelModel());
    });

    it('shows the naming panel and not the three plain pattern rows', async () => {
      const element = build();
      await settle();

      const labels = Array.from(element.shadowRoot.querySelectorAll('div[role="group"]')).map(
        (group) => group.getAttribute('aria-label')
      );
      expect(labels).toEqual(['Include deceased in name', 'Preview and recompute']);
      NAMING_KEYS.forEach((key) => {
        expect(element.shadowRoot.querySelector(`[data-key="${key}"]`)).toBeNull();
      });
      expect(
        element.shadowRoot.querySelector('h3[data-key="Household_Naming_Preview"]')
      ).not.toBeNull();
    });

    it('lands a search for a naming pattern on the panel', async () => {
      const element = build();
      await settle();
      const focus = jest.fn();
      const scrollIntoView = jest.fn();
      const originalFocus = HTMLElement.prototype.focus;
      const originalScroll = HTMLElement.prototype.scrollIntoView;
      HTMLElement.prototype.focus = focus;
      HTMLElement.prototype.scrollIntoView = scrollIntoView;
      try {
        element.shadowRoot.querySelector('c-settings-search').dispatchEvent(
          new CustomEvent('settingselect', {
            detail: { section: 'Households', key: 'Formal_Greeting_Pattern__c' }
          })
        );
        await settle();
      } finally {
        HTMLElement.prototype.focus = originalFocus;
        HTMLElement.prototype.scrollIntoView = originalScroll;
      }

      expect(scrollIntoView).toHaveBeenCalledTimes(1);
      expect(focus).toHaveBeenCalledTimes(1);
      expect(focus.mock.instances[0].dataset.key).toBe('Household_Naming_Preview');
    });

    it('still lands a search for another Households setting on that setting', async () => {
      const element = build();
      await settle();
      const focus = jest.fn();
      const originalFocus = HTMLElement.prototype.focus;
      const originalScroll = HTMLElement.prototype.scrollIntoView;
      HTMLElement.prototype.focus = focus;
      HTMLElement.prototype.scrollIntoView = jest.fn();
      try {
        element.shadowRoot.querySelector('c-settings-search').dispatchEvent(
          new CustomEvent('settingselect', {
            detail: { section: 'Households', key: 'Include_Deceased_In_Name__c' }
          })
        );
        await settle();
      } finally {
        HTMLElement.prototype.focus = originalFocus;
        HTMLElement.prototype.scrollIntoView = originalScroll;
      }

      expect(focus.mock.instances[0].dataset.key).toBe('Include_Deceased_In_Name__c');
    });

    it('reloads when a feature is turned on, so its settings rows appear', async () => {
      const general = {
        canEdit: true,
        sections: [
          {
            name: 'General',
            settings: [
              {
                key: 'Feature_List',
                label: 'Features',
                description: null,
                dataType: 'Component',
                section: 'General',
                settingsObject: 'BarnCRM_Settings__c',
                component: 'featureSettings',
                navigationTarget: null,
                helpUrl: null,
                value: null,
                checked: false,
                options: []
              }
            ]
          }
        ]
      };
      getConsoleModel.mockResolvedValue(general);
      const element = build();
      await settle();
      await settle();
      expect(getConsoleModel).toHaveBeenCalledTimes(1);

      const panel = element.shadowRoot.querySelector(
        'h3[data-key="Feature_List"]'
      ).nextElementSibling;
      panel.dispatchEvent(new CustomEvent('featureturnedon', { detail: { key: 'Addresses' } }));
      await settle();

      expect(getConsoleModel).toHaveBeenCalledTimes(2);
    });

    it('asks a mounted panel to refresh after first-run setup finishes', async () => {
      const general = {
        canEdit: true,
        sections: [
          {
            name: 'General',
            settings: [
              {
                key: 'Feature_List',
                label: 'Features',
                description: null,
                dataType: 'Component',
                section: 'General',
                settingsObject: 'BarnCRM_Settings__c',
                component: 'featureSettings',
                navigationTarget: null,
                helpUrl: null,
                value: null,
                checked: false,
                options: []
              }
            ]
          }
        ]
      };
      getConsoleModel.mockResolvedValue(general);
      FeatureSettings.refreshCount = 0;
      const element = build();
      await settle();
      await settle();
      expect(FeatureSettings.refreshCount).toBe(0);

      element.shadowRoot
        .querySelector('c-first-run-setup')
        .dispatchEvent(new CustomEvent('setupfinished'));
      await settle();
      await settle();

      expect(getConsoleModel).toHaveBeenCalledTimes(2);
      expect(FeatureSettings.refreshCount).toBe(1);
    });

    it('keeps the plain pattern rows when the section has no naming panel', async () => {
      const withoutPanel = householdsWithPanelModel();
      withoutPanel.sections[0].settings = withoutPanel.sections[0].settings.filter(
        (setting) => setting.dataType !== 'Component'
      );
      getConsoleModel.mockResolvedValue(withoutPanel);
      const element = build();
      await settle();

      NAMING_KEYS.forEach((key) => {
        expect(element.shadowRoot.querySelector(`[data-key="${key}"]`)).not.toBeNull();
      });
    });
  });
});
