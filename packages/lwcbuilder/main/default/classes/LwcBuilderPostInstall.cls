/**
 * What the BarnCRM LWC Builder module does at install and at every upgrade (ADR-0203
 * `0203-lwc-builder-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Queue the job that gives the installer LWC Builder Admin (a permission set assignment is a
 *    setup object write).
 * 2. Give BarnCRM's roles their LWC Builder sets (`ModuleAccessSyncs`), queued for the same
 *    reason; the installer's job runs it after its own grant.
 *
 * Nothing else changes: a built component shows only where an admin places it.
 */
@NamespaceAccessible
public with sharing class LwcBuilderPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'LwcBuilder';

	/**
	 * Checkboxes that ship on, each turned on once in an org that saved the settings before it
	 * existed (QA-F2). Append only; `scripts/ci/check-setting-defaults.py` checks it.
	 */
	@TestVisible
	private static final List<Schema.SObjectField> SHIPPED_ON_ADDED_IN_UPGRADES = new List<Schema.SObjectField>{};

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public LwcBuilderPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps, with the given person standing in for the installer, then the module's
	 * key added to the setup marker. Never throws.
	 */
	public void runSetup(Id installerId) {
		ShippedDefaultUpgrades.apply(
			MODULE_KEY,
			LWC_Builder_Settings__c.SObjectType,
			SHIPPED_ON_ADDED_IN_UPGRADES
		);
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
