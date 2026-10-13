import { createElement } from 'lwc';
import SettingsConsole from 'c/settingsConsole';
import getConsoleModel from '@salesforce/apex/SettingsController.getConsoleModel';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import getRecentChanges from '@salesforce/apex/SettingsController.getRecentChanges';
import * as navigation from 'lightning/navigation';

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

// Reached through the module namespace rather than by name: a wire adapter may only be named
// in a @wire decorator, and a test drives it through the stub's emit.
function openSection(name) {
  navigation.CurrentPageReference.emit({ state: { c__section: name } });
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
    expect(inputs).toHaveLength(2);
    expect(inputs[0].value).toBe('The {LastName} Family');
    expect(inputs[1].checked).toBe(true);

    const help = element.shadowRoot.querySelector('a[target="_blank"]');
    expect(help).not.toBeNull();
    expect(help.href).toContain('household-naming.md');
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

  it('opens the section a setup step asked for', async () => {
    const element = build();
    openSection('General');
    await settle();

    const combobox = element.shadowRoot.querySelector('lightning-combobox');
    expect(combobox).not.toBeNull();
    expect(combobox.value).toBe('Standalone');
  });

  it('offers a module its own page instead of trying to render it', async () => {
    const element = build();
    openSection('Giving');
    await settle();

    const button = element.shadowRoot.querySelector('lightning-button[data-target]');
    expect(button).not.toBeNull();
    expect(button.dataset.target).toBe('Giving_Settings');
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
    expect(groups).toHaveLength(2);
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
});
