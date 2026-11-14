/**
 * What the BarnCRM Portal Builder module does at install and at every upgrade (ADR-0185
 * `0185-portal-builder-off-platform-portal-api.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Queue the job that gives the installer Portal Builder Admin (a permission set assignment is
 *    a setup object write).
 * 2. Give the set to BarnCRM Admin holders (`ModuleAccessSyncs`), queued for the same reason; the
 *    installer's job runs it after its own grant.
 *
 * Nothing is switched on: Portal Sign-In ships off, and no portal exists until an admin adds one.
 */
@NamespaceAccessible
public with sharing class PortalPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'Portal';

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public PortalPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps, with the given person standing in for the installer, then the module's
	 * key added to the setup marker. Never throws.
	 */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
