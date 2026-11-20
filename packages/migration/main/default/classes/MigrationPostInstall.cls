/**
 * What the BarnCRM Migration package does at install and at every upgrade (ADR-0232).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Mark the package's setup as run (`ModuleSetups`).
 * 2. Queue the job that gives the installer and every BarnCRM Admin holder Migration Admin
 *    (`ModuleAccessSyncs`; a permission set assignment is a setup object write).
 *
 * Nothing else changes: the package stores no settings, and its records are Admin Journal rows
 * and Import Batches, which Core owns.
 */
@NamespaceAccessible
public with sharing class MigrationPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'Migration';

	/** Called by the platform after the package is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public MigrationPostInstall() {
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
