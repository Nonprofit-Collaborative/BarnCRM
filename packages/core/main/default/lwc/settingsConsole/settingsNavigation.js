import ORGANIZATION from '@salesforce/label/c.Core_Settings_NavGroup_Organization';
import PEOPLE from '@salesforce/label/c.Core_Settings_NavGroup_People';
import DATA from '@salesforce/label/c.Core_Settings_NavGroup_Data';
import FUNDRAISING from '@salesforce/label/c.Core_Settings_NavGroup_Fundraising';
import PROGRAMS from '@salesforce/label/c.Core_Settings_NavGroup_Programs';
import MORE from '@salesforce/label/c.Core_Settings_NavGroup_More';
import SYSTEM from '@salesforce/label/c.Core_Settings_NavGroup_System';

/**
 * The section list in groups, each section with its icon. Sections are matched by their stored
 * name (case ignored). A section no group names, such as one a later module adds, goes in More,
 * which sits before System so Error Log is always the last item. A group with no section in
 * this org is left out. Rollups sits under Data, not Fundraising: the Rollup Builder is used
 * without Giving, in Standard Edition too (owner QA, 2026-10-31).
 */
const GROUPS = [
  {
    name: 'organization',
    label: ORGANIZATION,
    sections: [
      ['General', 'utility:settings'],
      ['Organization', 'utility:company']
    ]
  },
  {
    name: 'people',
    label: PEOPLE,
    sections: [
      ['People and Households', 'utility:groups'],
      ['Addresses', 'utility:location']
    ]
  },
  {
    name: 'data',
    label: DATA,
    sections: [
      ['Import', 'utility:upload'],
      ['Duplicate Matching', 'utility:merge'],
      ['Rollups', 'utility:summary'],
      ['Org Optimizer', 'utility:magicwand']
    ]
  },
  {
    name: 'fundraising',
    label: FUNDRAISING,
    sections: [
      ['Giving', 'utility:moneybag'],
      ['Receipts', 'utility:email']
    ]
  },
  { name: 'programs', label: PROGRAMS, sections: [['Volunteers', 'utility:people']] },
  { name: 'more', label: MORE, sections: [] },
  {
    name: 'system',
    label: SYSTEM,
    sections: [
      ['Modules', 'utility:apps'],
      ['Access', 'utility:lock'],
      ['Automation', 'utility:flow'],
      ['Integrations', 'utility:connected_apps'],
      ['Health', 'utility:success'],
      ['Error Log', 'utility:error']
    ]
  }
];

const OTHER_ICON = 'utility:settings';

/** The groups to show for these section names: `{ name, label, items: [{ name, label, iconName }] }`. */
export function navigationGroups(sectionNames) {
  const remaining = new Map(sectionNames.map((name) => [String(name).toLowerCase(), name]));
  const groups = GROUPS.map((group) => {
    const items = [];
    group.sections.forEach(([sectionName, iconName]) => {
      const key = sectionName.toLowerCase();
      if (remaining.has(key)) {
        const name = remaining.get(key);
        remaining.delete(key);
        items.push({ name, label: name, iconName });
      }
    });
    return { name: group.name, label: group.label, items };
  });
  const more = groups.find((group) => group.name === 'more');
  remaining.forEach((name) => more.items.push({ name, label: name, iconName: OTHER_ICON }));
  return groups.filter((group) => group.items.length > 0);
}
