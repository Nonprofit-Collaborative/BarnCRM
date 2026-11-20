/**
 * What the BarnCRM Sample Data package does at install and at every upgrade (ADR-0233
 * `0233-org-optimizer-and-sample-data-modules.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Mark the package's setup as run (`ModuleSetups`).
 * 2. Queue the job that gives the installer and every BarnCRM Admin holder Sample Data
 *    (`ModuleAccessSyncs`; a permission set assignment is a setup object write).
 *
 * Nothing else changes: the package stores no settings, and the sample records are Core's
 * objects, flagged Sample Data.
 */
@NamespaceAccessible
public with sharing class SampleDataPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'SampleData';

	/** Called by the platform after the package is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public SampleDataPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps, with the given person standing in for the installer, then the
	 * package's key added to the setup marker. Never throws.
	 */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
