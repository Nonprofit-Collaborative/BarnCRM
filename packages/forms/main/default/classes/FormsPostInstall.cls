/**
 * What the BarnCRM Forms module does at install and at every upgrade (ADR-0175
 * `0175-forms-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Queue the job that gives the installer the Forms Admin permission set. Queued because a
 *    permission set assignment is a setup object write.
 * 2. Give the Forms sets to BarnCRM's roles (`ModuleAccessSyncs`), queued for the same reason. The
 *    installer's job runs it after its own grant; with no installer it is queued alone.
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what Finish
 * Setup runs for a module copied into an org by hand (FS1, `ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class FormsPostInstall implements InstallHandler, ModuleSetup {
	/** The module's key in the module catalog and the setup marker. */
	public static final String MODULE_KEY = 'Forms';

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public FormsPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps (see the class comment), with the given person standing in for the
	 * installer, then the module's key added to the setup marker. Never throws.
	 *
	 * @param installerId the person to give Forms Admin, or null for nobody
	 */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
