/**
 * What BarnCRM Mirror does for itself at install and at every upgrade: create the
 * Automation page's switch rows for the automations Mirror registers, starting with
 * Campaign sync (ADR-0056 on Campaign sync). Core's and Giving's scripts run before Mirror's
 * registry rows exist, so they cannot create them, and Health Check would otherwise report the
 * switches as missing on every fresh install. It does not create `Mirror_Settings__c`: the
 * Campaign sync setting's field default of false already reads as off.
 *
 * The work is Core's `AutomationControl.ensureDefaultsDuringInstall`, which leaves every
 * existing row as the administrator left it and never throws, so an install is never aborted
 * by this step.
 */
public with sharing class MirrorPostInstall implements InstallHandler {
    private static final String SWITCH_CONTEXT = 'MirrorPostInstall.ensureAutomationSwitches';

    /**
     * Called by the platform after the package is installed or upgraded.
     *
     * @param context what the platform knows about this install, unused here because the
     *        switches belong to the org rather than to whoever pressed Install
     */
    public void onInstall(InstallContext context) {
        AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
    }
}
