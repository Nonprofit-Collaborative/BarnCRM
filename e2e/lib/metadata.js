// The BarnCRM Lightning apps and their tabs, read from the repository's metadata so the smoke
// list never drifts from the source: packages/*/main/default/applications/*.app-meta.xml for the
// apps and their <tabs>, the module catalog for the tabs modules add to them, and
// packages/*/main/default/tabs/*.tab-meta.xml for each tab's kind.

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PACKAGES = path.join(ROOT, 'packages');

// Platform pages with no BarnCRM code on them: opening them tests Salesforce, not BarnCRM.
// standard-Contact and standard-Account stay in, since BarnCRM changes their pages.
const PLATFORM_ONLY_TABS = new Set(['standard-report', 'standard-Dashboard', 'standard-home']);

function tagValues(xml, tag) {
  const pattern = new RegExp(`<${tag}>\\s*([^<]*?)\\s*</${tag}>`, 'g');
  return [...xml.matchAll(pattern)].map((match) => match[1]);
}

function packageFiles(folder, suffix) {
  const files = [];
  for (const pkg of fs.readdirSync(PACKAGES).sort()) {
    const dir = path.join(PACKAGES, pkg, 'main', 'default', folder);
    if (!fs.existsSync(dir)) {
      continue;
    }
    for (const file of fs.readdirSync(dir).sort()) {
      // The synced folder can hold "Name 2.app-meta.xml" copies; they are not source.
      if (file.endsWith(suffix) && !/ \d+\./.test(file)) {
        files.push({ pkg, name: file.slice(0, -suffix.length), file: path.join(dir, file) });
      }
    }
  }
  return files;
}

/** Each tab file by tab name: true when the tab is an object tab. */
function tabKinds() {
  const kinds = new Map();
  for (const tab of packageFiles('tabs', '.tab-meta.xml')) {
    const xml = fs.readFileSync(tab.file, 'utf8');
    kinds.set(tab.name, tagValues(xml, 'customObject')[0] === 'true');
  }
  return kinds;
}

/** The path that opens a tab: an object's list view, or the page of a Lightning page tab. */
function tabPath(tab, kinds) {
  if (tab.startsWith('standard-')) {
    return `/o/${tab.slice('standard-'.length)}/list`;
  }
  const isObject = kinds.has(tab) ? kinds.get(tab) : tab.endsWith('__c');
  return isObject ? `/o/${tab}/list` : `/n/${tab}`;
}

/** A custom metadata record's values by field. */
function recordValues(xml) {
  const values = {};
  const pattern = /<field>\s*(\w+)\s*<\/field>\s*<value[^>]*?(?:\/>|>([^<]*)<\/value>)/g;
  for (const match of xml.matchAll(pattern)) {
    values[match[1]] = (match[2] || '').trim();
  }
  return values;
}

/**
 * The module tabs the source deploy adds to each app from outside the app's package, by app
 * name, from the module catalog (BarnCRM_Module records), by the rule of
 * scripts/org/module-app-tabs.py: a host app another package ships takes the module's staff and
 * admin tabs, a module with no app puts its staff tabs in BarnCRM Console, and every admin tab
 * joins BarnCRM Admin Console.
 */
function hostedTabs(appFolders) {
  const hosted = new Map();
  const add = (app, tab) => hosted.set(app, [...(hosted.get(app) || []), tab]);
  const rows = packageFiles('customMetadata', '.md-meta.xml').filter(
    (file) => file.pkg === 'core' && file.name.startsWith('BarnCRM_Module.')
  );
  for (const row of rows) {
    const values = recordValues(fs.readFileSync(row.file, 'utf8'));
    const folder = values.Package_Folder__c;
    const app = values.App_Name__c;
    const home = app && appFolders.has(app) && appFolders.get(app) !== folder ? app : null;
    const own = Boolean(app) && appFolders.get(app) === folder;
    const shipped = (entry) => {
      const name = entry.split(':')[0].trim();
      const file = path.join(PACKAGES, folder, 'main', 'default', 'tabs', `${name}.tab-meta.xml`);
      return name && fs.existsSync(file) ? name : null;
    };
    const staffApps = home ? [home] : own ? [] : ['BarnCRM'];
    const adminApps = ['BarnCRM_Admin_Console', ...(home ? [home] : [])];
    for (const [field, apps] of [
      ['Staff_Tabs__c', staffApps],
      ['Admin_Tabs__c', adminApps]
    ]) {
      for (const tab of (values[field] || '').split(';').map(shipped).filter(Boolean)) {
        apps.forEach((target) => add(target, tab));
      }
    }
  }
  return hosted;
}

/**
 * Every BarnCRM app with its label, navigation type and tabs, in package order: the tabs its
 * own file lists, then the module tabs the source deploy adds to it.
 */
function barnApps() {
  const kinds = tabKinds();
  const files = packageFiles('applications', '.app-meta.xml');
  const hosted = hostedTabs(new Map(files.map((app) => [app.name, app.pkg])));
  return files.map((app) => {
    const xml = fs.readFileSync(app.file, 'utf8');
    const own = tagValues(xml, 'tabs');
    const added = (hosted.get(app.name) || []).filter((tab) => !own.includes(tab));
    return {
      name: app.name,
      pkg: app.pkg,
      label: tagValues(xml, 'label')[0],
      console: tagValues(xml, 'navType')[0] === 'Console',
      tabs: [...own, ...new Set(added)].map((tab) => ({
        name: tab,
        path: tabPath(tab, kinds),
        platformOnly: PLATFORM_ONLY_TABS.has(tab)
      }))
    };
  });
}

/** The names of every Lightning web component bundle BarnCRM ships, for console attribution. */
function barnComponents() {
  const names = new Set();
  for (const pkg of fs.readdirSync(PACKAGES)) {
    const dir = path.join(PACKAGES, pkg, 'main', 'default', 'lwc');
    if (fs.existsSync(dir)) {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory() && !entry.name.includes(' ')) {
          names.add(entry.name);
        }
      }
    }
  }
  return names;
}

module.exports = { barnApps, barnComponents };
