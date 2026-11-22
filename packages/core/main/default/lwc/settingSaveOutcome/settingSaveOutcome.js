/**
 * Follows a settings save to its end (ADR-0238 settings as custom metadata, R-STV2). A save is one
 * metadata deployment; this asks SettingsController.getSaveOutcome about every two seconds, for up
 * to two minutes, and resolves to { status, message }: Succeeded, Failed (message is Salesforce's
 * reason) or Pending (still running when it stopped asking). No deployment Id means the save is
 * already done (nothing changed, or a test). The BarnCRM Settings tab and every module's own
 * settings page use it, so they all follow a save the same way.
 */
import getSaveOutcome from '@salesforce/apex/SettingsController.getSaveOutcome';

export const POLL_INTERVAL_MS = 2000;
export const POLL_ATTEMPTS = 60;

function pause(ms) {
  return new Promise((resolve) => {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(resolve, ms);
  });
}

export async function waitForSave(deploymentId, attempts = POLL_ATTEMPTS) {
  if (!deploymentId) {
    return { status: 'Succeeded' };
  }
  for (let attempt = 0; attempt < attempts; attempt++) {
    // eslint-disable-next-line no-await-in-loop
    await pause(POLL_INTERVAL_MS);
    // eslint-disable-next-line no-await-in-loop
    const outcome = await getSaveOutcome({ deploymentId });
    const status = outcome && outcome.status;
    if (status === 'Succeeded' || status === 'Failed') {
      return { status, message: outcome.message };
    }
  }
  return { status: 'Pending' };
}
