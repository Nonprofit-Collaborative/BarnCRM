import { createElement } from 'lwc';
import SettingsConsole from 'c/settingsConsole';
import getConsoleModel from '@salesforce/apex/SettingsController.getConsoleModel';
import getRecentChanges from '@salesforce/apex/SettingsController.getRecentChanges';
import * as navigation from 'lightning/navigation';
import { groupRows, findBox } from '../settingsGroups';

// The boxed sub-sections on every BarnCRM Settings page, and the People and Households page
// that merged the Households and Relationships pages (P1).

jest.mock('@salesforce/label/c.Core_SettingsGroup_People', () => ({ default: 'People' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_SettingsGroup_Households', () => ({ default: 'Households' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_SettingsGroup_HouseholdNames',
  () => ({ default: 'Household Names and Greetings' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SettingsGroup_Relationships',
  () => ({ default: 'Relationships' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SettingsGroup_Preferences',
  () => ({ default: 'Preferences' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SettingsGroup_RollupBuilder',
  () => ({ default: 'Rollup Builder' }),
  { virtual: true }
);
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

const PAGE = 'People and Households';

function row(key, label, section = PAGE, dataType = 'Checkbox') {
  return {
    key,
    label,
    description: null,
    dataType,
    section,
    component: null,
    navigationTarget: dataType === 'Component' ? 'Data_Hygiene' : null,
    helpUrl: null,
    value: 'false',
    checked: false,
    options: []
  };
}

/** The merged page as Core ships it, plus a row no box names, and a General page. */
function peopleAndHouseholdsModel() {
  return {
    canEdit: true,
    sections: [
      {
        name: PAGE,
        settings: [
          row('Household_Membership_Mode__c', 'How people belong to a household'),
          row('Auto_Create_Households__c', 'Create a household automatically'),
          row('Delete_Empty_Households__c', 'Delete a household once it is empty'),
          row('Keep_Households_Of_Deleted_People__c', 'Keep the households of deleted people'),
          row('Household_Naming_Preview', 'Preview and Recompute', PAGE, 'Component'),
          row('Include_Deceased_In_Name__c', 'Include people who have died in names'),
          row('Relationship_Auto_Reciprocal__c', 'Keep both sides of relationships in step'),
          row('Brand_New_Setting__c', 'A setting added after this list was written')
        ]
      },
      {
        name: 'General',
        settings: [
          row('Coexistence_Mode__c', 'Coexistence mode', 'General'),
          row('Not_Yet_Grouped__c', 'A new General setting', 'General')
        ]
      },
      {
        name: 'Duplicate Matching',
        settings: [row('Duplicate_Review', 'Duplicate Matching', 'Duplicate Matching', 'Component')]
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

function boxes(element) {
  return Array.from(element.shadowRoot.querySelectorAll('section.slds-box')).map((box) => ({
    id: box.dataset.box,
    heading: box.querySelector('h2').textContent.trim(),
    keys: Array.from(box.querySelectorAll('div[role="group"]')).map(
      (group) => group.querySelector('[data-key]').dataset.key
    )
  }));
}

function openSection(name) {
  navigation.CurrentPageReference.emit({ state: { c__section: name } });
}

describe('c-settings-console boxed sub-sections (P1)', () => {
  beforeEach(() => {
    getConsoleModel.mockResolvedValue(peopleAndHouseholdsModel());
    getRecentChanges.mockResolvedValue([]);
  });

  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows People and Households as People, Households, naming and Relationships boxes', async () => {
    const element = build();
    await settle();

    const shown = boxes(element);
    expect(shown.map((box) => box.heading)).toEqual([
      'People',
      'Households',
      'Household Names and Greetings',
      'Relationships'
    ]);
    // The Duplicates row is on the Duplicate Matching page (batch 10), not in the People box.
    expect(shown[0].keys).toEqual(['Household_Membership_Mode__c', 'Auto_Create_Households__c']);
    expect(shown[2].keys).toEqual(['Household_Naming_Preview', 'Include_Deceased_In_Name__c']);
    expect(shown[3].keys).toEqual(['Relationship_Auto_Reciprocal__c']);
    const box = element.shadowRoot.querySelector('section.slds-box');
    expect(box.getAttribute('aria-labelledby')).toBe(box.querySelector('h2').id);
  });

  it('puts a row no box names in the page fallback box, so no setting disappears', async () => {
    const element = build();
    await settle();

    const shown = boxes(element);
    expect(shown[1].keys).toEqual([
      'Delete_Empty_Households__c',
      'Keep_Households_Of_Deleted_People__c',
      'Brand_New_Setting__c'
    ]);
    const everyKey = shown.flatMap((one) => one.keys);
    expect(everyKey).toHaveLength(peopleAndHouseholdsModel().sections[0].settings.length);

    openSection('General');
    await settle();
    expect(boxes(element)).toEqual([
      {
        id: 'Preferences',
        heading: 'Preferences',
        keys: ['Coexistence_Mode__c', 'Not_Yet_Grouped__c']
      }
    ]);
  });

  it('shows a page with no boxes listed in one box titled with the page name', async () => {
    const element = build();
    await settle();
    openSection('Duplicate Matching');
    await settle();

    expect(boxes(element)).toEqual([
      {
        id: 'Duplicate Matching',
        heading: 'Duplicate Matching',
        keys: ['Duplicate_Review']
      }
    ]);
    // A panel alone in a box of the same name keeps its heading for focus, hidden from view.
    const panelHeading = element.shadowRoot.querySelector('h3[data-key="Duplicate_Review"]');
    expect(panelHeading.className).toContain('slds-assistive-text');
  });

  it('shows the unsaved default note and Keep this setting inside the box (RM1 with P1)', async () => {
    const model = peopleAndHouseholdsModel();
    const kept = model.sections[0].settings.find((one) => one.key === 'Delete_Empty_Households__c');
    kept.unsavedDefault = true;
    getConsoleModel.mockResolvedValue(model);
    const element = build();
    await settle();

    const box = element.shadowRoot.querySelector('section[data-box="Households"]');
    expect(
      box.querySelector('lightning-button[data-keep="Delete_Empty_Households__c"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('lightning-button[data-keep]')).toHaveLength(1);
  });

  it('keeps a panel heading visible when the box holds more than the panel', async () => {
    const element = build();
    await settle();

    const heading = element.shadowRoot.querySelector('h3[data-key="Household_Naming_Preview"]');
    expect(heading.className).toContain('slds-text-heading_small');
    expect(heading.className).not.toContain('slds-assistive-text');
  });

  it.each([
    ['Relationships', 'Relationships'],
    ['households', 'Households'],
    ['Household Names and Greetings', 'Household Names and Greetings'],
    ['People', 'People']
  ])('opens People and Households at the %s box when a link names it', async (requested, boxId) => {
    const scrollIntoView = jest.fn();
    const focus = jest.fn();
    const originalScroll = HTMLElement.prototype.scrollIntoView;
    const originalFocus = HTMLElement.prototype.focus;
    HTMLElement.prototype.scrollIntoView = scrollIntoView;
    HTMLElement.prototype.focus = focus;
    try {
      const element = build();
      await settle();
      openSection('General');
      await settle();
      openSection(requested);
      await settle();

      const selected = element.shadowRoot.querySelector('lightning-vertical-navigation');
      expect(selected.selectedItem).toBe(PAGE);
      const box = element.shadowRoot.querySelector(`section[data-box="${boxId}"]`);
      expect(scrollIntoView.mock.contexts).toContain(box);
      expect(focus.mock.contexts).toContain(box.querySelector('h2'));
    } finally {
      HTMLElement.prototype.scrollIntoView = originalScroll;
      HTMLElement.prototype.focus = originalFocus;
    }
  });

  it('shows the duplicate rules note on Duplicate Matching, not on People and Households', async () => {
    const element = build();
    await settle();

    let notes = element.shadowRoot.querySelector('c-settings-setup-notes');
    expect(notes ? notes.shadowRoot.querySelector('[data-key="duplicates"]') : null).toBeNull();

    openSection('Duplicate Matching');
    await settle();
    notes = element.shadowRoot.querySelector('c-settings-setup-notes');
    expect(notes.shadowRoot.querySelector('[data-key="duplicates"]')).not.toBeNull();
  });
});

/** Every Setting Definition row the packages ship, as the console's rows, by page. */
function shippedRowsByPage() {
  // Jest runs from the repository root (jest.config.js).
  const fs = require('fs');
  const path = require('path');
  const byPage = {};
  fs.readdirSync('packages').forEach((pkg) => {
    const dir = path.join('packages', pkg, 'main', 'default', 'customMetadata');
    if (!fs.existsSync(dir)) {
      return;
    }
    fs.readdirSync(dir)
      .filter((file) => file.startsWith('Setting_Definition.'))
      .forEach((file) => {
        const xml = fs.readFileSync(path.join(dir, file), 'utf8');
        const value = (field) => {
          const match = xml.match(
            new RegExp(`<field>${field}</field>\\s*<value[^>]*>([^<]*)</value>`)
          );
          return match ? match[1] : null;
        };
        const developerName = file.replace('Setting_Definition.', '').replace('.md-meta.xml', '');
        const component = value('Data_Type__c') === 'Component';
        const key = component ? developerName : value('Setting_Key__c');
        const page = value('Section__c');
        (byPage[page] = byPage[page] || []).push({ key });
      });
  });
  return byPage;
}

describe('settingsGroups against the shipped registry', () => {
  it('drops no shipped row on any page', () => {
    const byPage = shippedRowsByPage();

    expect(Object.keys(byPage).length).toBeGreaterThan(10);
    Object.entries(byPage).forEach(([page, rows]) => {
      const shown = groupRows(page, rows).flatMap((box) => box.rows);
      expect(shown).toHaveLength(rows.length);
    });
  });

  it('puts the rows batches 10 and 11 added in the boxes that name them', () => {
    const byPage = shippedRowsByPage();
    const boxOf = (page, key) =>
      groupRows(page, byPage[page]).find((box) => box.rows.some((one) => one.key === key));

    expect(boxOf('Addresses', 'Contact_Address_Change_Behavior__c').id).toBe('Address Updates');
    expect(boxOf('Addresses', 'Address_Card_Fields__c').id).toBe('Address Card');
    expect(boxOf('General', 'App_Navigation_Style__c').id).toBe('Preferences');
    expect(boxOf('Rollups', 'Nightly_Run_Hour__c').id).toBe('Rollup Processing');
    const duplicateBoxes = groupRows('Duplicate Matching', byPage['Duplicate Matching']);
    expect(duplicateBoxes).toHaveLength(1);
    expect(duplicateBoxes[0].id).toBe('Duplicate Matching');
    expect(duplicateBoxes[0].rows.map((one) => one.key)).toEqual(
      expect.arrayContaining([
        'Duplicate_Review',
        'Fuzzy_Match_Threshold__c',
        'Merge_Default_Rule__c'
      ])
    );
  });
});

describe('settingsGroups', () => {
  it('drops no row and shows no empty box', () => {
    const rows = [{ key: 'Rollup_Definitions' }, { key: 'Some_Module_Row__c' }];

    const result = groupRows('Rollups', rows);

    expect(result.map((box) => box.id)).toEqual(['Rollup Processing', 'Rollup Builder']);
    expect(result[0].rows).toEqual([{ key: 'Some_Module_Row__c' }]);
    expect(groupRows('Volunteers', [])).toEqual([]);
    expect(groupRows('Unknown Page', [])).toEqual([]);
  });

  it('finds a box only on a page the console has, ignoring case and spacing', () => {
    expect(findBox([PAGE], ' relationships ')).toEqual({ page: PAGE, box: 'Relationships' });
    expect(findBox(['General'], 'Relationships')).toBeUndefined();
    expect(findBox([PAGE], 'Nowhere')).toBeUndefined();
    expect(findBox([PAGE], '')).toBeUndefined();
  });

  it('names every box heading in a custom label written in title case', () => {
    // Jest runs from the repository root (jest.config.js).
    const fs = require('fs');
    const xml = fs.readFileSync(
      'packages/core/main/default/labels/SettingsGroups.labels-meta.xml',
      'utf8'
    );
    const source = fs.readFileSync(
      'packages/core/main/default/lwc/settingsConsole/settingsGroups.js',
      'utf8'
    );
    const labels = {};
    for (const match of xml.matchAll(/<fullName>(.*?)<\/fullName>[\s\S]*?<value>(.*?)<\/value>/g)) {
      labels[match[1]] = match[2];
    }
    const imported = Array.from(source.matchAll(/label\/c\.(\w+)'/g)).map((match) => match[1]);

    expect(imported.length).toBeGreaterThan(0);
    const small = new Set(['a', 'an', 'and', 'for', 'in', 'of', 'on', 'or', 'the', 'to']);
    imported.forEach((name) => {
      expect(labels[name]).toBeDefined();
      labels[name].split(' ').forEach((word, index) => {
        const lowerAllowed = index > 0 && small.has(word);
        expect(lowerAllowed || /^[A-Z]/.test(word)).toBe(true);
      });
    });
  });
});
