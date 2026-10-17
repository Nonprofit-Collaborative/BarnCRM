import { setTabIcon, setTabLabel } from 'lightning/platformWorkspaceApi';

/**
 * Names the console tab a Rollups component sits in, through the Workspace API. A copy of
 * Core's `c/workspaceTabs` `labelTab`, kept in this package because that Core module is not
 * exposed, and a module component imports only what its own package ships or Core exposes.
 *
 * The caller wires `@wire(EnclosingTabId) enclosingTabId` and passes itself. Outside a console
 * the tab id is null and this does nothing. Safe to call on every render: the console is only
 * asked again when the label, icon or tab changed.
 */

const appliedLabels = new WeakMap();

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
