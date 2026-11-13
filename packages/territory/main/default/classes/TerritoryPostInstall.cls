/**
 * What the BarnCRM Territory Management module does at install and at every upgrade (ADR-0205
 * `0205-territory-management-module.md`). Nothing here changes a record: territories are the
 * admin's, and the nightly step ships off.
 *
 * 1. Add the module to Core's setup marker (`ModuleSetups`), which Finish Setup also runs.
 * 2. Queue the job that gives the installer Territory Admin (a permission set assignment is a
 *    setup object write), which then gives BarnCRM's roles their sets
 *    (`ModuleAccessSyncs`). Every failure goes to the Error Log; none can abort an install.
 */
@NamespaceAccessible
public with sharing class TerritoryPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'Territory';

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public TerritoryPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/** The install's steps, with the given person standing in for the installer. Never throws. */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
