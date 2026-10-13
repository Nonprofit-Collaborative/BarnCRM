import {
  getTabInfo,
  openSubtab,
  refreshTab,
  setTabIcon,
  setTabLabel
} from 'lightning/platformWorkspaceApi';

/**
 * Console tab handling for Core components, through the Workspace API.
 *
 * A component that uses this module wires the tab it sits in and passes itself:
 *
 *   @wire(EnclosingTabId) enclosingTabId;
 *
 * EnclosingTabId is null outside a console app, so every function here does nothing and
 * reports false there. The caller then keeps the NavigationMixin navigation it always had:
 * standard navigation, and an org that uses another app, behave exactly as before.
 */

const appliedLabels = new WeakMap();

/** The workspace tab a tab belongs to: itself, or the parent of a subtab. */
async function workspaceTabId(tabId) {
  const info = await getTabInfo(tabId);
  return info && info.isSubtab && info.parentTabId ? info.parentTabId : tabId;
}

/**
 * Opens a record as a subtab of the workspace tab the component sits in. The target is what
 * openSubtab takes: `{ recordId }`, `{ pageReference }` or `{ url }`. Resolves true when the
 * console opened it, false when the caller should navigate the usual way.
 */
export async function openInWorkspace(host, target) {
  if (!host || !host.enclosingTabId) {
    return false;
  }
  try {
    await openSubtab(await workspaceTabId(host.enclosingTabId), { ...target, focus: true });
    return true;
  } catch {
    return false;
  }
}

/**
 * The click handler body for a link to a record. Outside a console, and for a click that
 * asks for a new browser tab or window, it does nothing and the browser follows the link as
 * it always did. In a console it keeps the browser from leaving and opens the record as a
 * subtab instead; when the console refuses, `fallback` runs (the caller's NavigationMixin
 * navigation). Returns whether it took the click.
 */
export function followLinkInWorkspace(host, event, target, fallback) {
  const newWindow = event.button > 0 || event.ctrlKey || event.metaKey || event.shiftKey;
  if (!host || !host.enclosingTabId || newWindow) {
    return false;
  }
  event.preventDefault();
  openInWorkspace(host, target).then((opened) => {
    if (!opened) {
      fallback();
    }
  });
  return true;
}

/**
 * Names the console tab the component sits in, with an icon. Safe to call on every render:
 * the console is only asked again when the label, icon or tab changed.
 */
export async function labelTab(host, label, iconName) {
  const tabId = host && host.enclosingTabId;
  if (!tabId || !label) {
    return false;
  }
  const key = `${tabId}|${label}|${iconName}`;
  if (appliedLabels.get(host) === key) {
    return true;
  }
  appliedLabels.set(host, key);
  try {
    await setTabLabel(tabId, label);
    if (iconName) {
      await setTabIcon(tabId, iconName, { iconAlt: label });
    }
    return true;
  } catch {
    appliedLabels.delete(host);
    return false;
  }
}

/** Reloads the console tab the component sits in, after an action changed what it shows. */
export async function refreshEnclosingTab(host) {
  if (!host || !host.enclosingTabId) {
    return false;
  }
  try {
    await refreshTab(host.enclosingTabId, { includeAllSubtabs: false });
    return true;
  } catch {
    return false;
  }
}
