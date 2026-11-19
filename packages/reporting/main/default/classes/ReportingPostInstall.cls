/**
 * What the BarnCRM Advanced Reporting module does at install and at every upgrade (ADR-NEXT
 * advanced reporting).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Mark the module's setup as run (`ModuleSetups`).
 * 2. Queue the job that gives the installer Advanced Reporting Admin and BarnCRM's roles their
 *    Advanced Reporting sets (`ModuleAccessSyncs`; a permission set assignment is a setup
 *    object write).
 *
 * Nothing else changes: the module stores no settings and no records, and the shipped dashboard
 * templates are a static resource.
 */
@NamespaceAccessible
public with sharing class ReportingPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'Reporting';

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public ReportingPostInstall() {
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
