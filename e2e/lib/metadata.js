// The BarnCRM Lightning apps and their tabs, read from the repository's metadata so the smoke
// list never drifts from the source: packages/*/main/default/applications/*.app-meta.xml for the
// apps and their <tabs>, and packages/*/main/default/tabs/*.tab-meta.xml for each tab's kind.

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

/** Every BarnCRM app with its label, navigation type and tabs, in package order. */
function barnApps() {
  const kinds = tabKinds();
  return packageFiles('applications', '.app-meta.xml').map((app) => {
    const xml = fs.readFileSync(app.file, 'utf8');
    return {
      name: app.name,
      pkg: app.pkg,
      label: tagValues(xml, 'label')[0],
      console: tagValues(xml, 'navType')[0] === 'Console',
      tabs: tagValues(xml, 'tabs').map((tab) => ({
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
