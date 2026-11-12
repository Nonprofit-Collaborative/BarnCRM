import tabApiNames from '@salesforce/apex/NamespaceUtil.tabApiNames';

/**
 * Packaged tab names as the org needs them. Once the namespace is set every packaged tab
 * carries its prefix, and Lightning components never build that name themselves
 * (dynamic-apex.md section 4): Apex qualifies it and this module remembers the answer for the
 * page. Components name a tab as written (`Find`) and open it with `tabPageReference`.
 */
const known = new Map();

/** Asks Apex once per page for the tabs not yet known; on failure a tab keeps its own name. */
export async function loadTabNames(tabs) {
  const missing = [...new Set(tabs || [])].filter((tab) => tab && !known.has(tab));
  if (!missing.length) {
    return;
  }
  try {
    const names = (await tabApiNames({ tabs: missing })) || {};
    missing.forEach((tab) => known.set(tab, names[tab] || tab));
  } catch {
    // With no namespace (today, and every unmanaged org) the name as written is the answer.
  }
}

/** The tab's API name, once loadTabNames has run for it; the name as written until then. */
export function tabApiName(tab) {
  return known.get(tab) || tab;
}

/** A page reference that opens the tab, with optional page state. */
export async function tabPageReference(tab, state) {
  await loadTabNames([tab]);
  const reference = { type: 'standard__navItemPage', attributes: { apiName: tabApiName(tab) } };
  return state ? { ...reference, state } : reference;
}
