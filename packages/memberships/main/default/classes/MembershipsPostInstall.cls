/**
 * What the BarnCRM Memberships module does at install and at every upgrade (ADR-0206
 * `0206-memberships-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Turn on, once, a ship-on setting added in an upgrade (Core's `ShippedDefaultUpgrades`).
 * 2. Queue the job that gives the installer Memberships Admin (a permission set assignment is a
 *    setup object write).
 * 3. Give the Memberships sets to BarnCRM's roles (`ModuleAccessSyncs`), queued for the same
 *    reason.
 *
 * Nothing else is set up: the nightly step joins Core's nightly run by itself, and reminders ship
 * off, so a fresh install emails nobody.
 */
@NamespaceAccessible
public with sharing class MembershipsPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'Memberships';

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
	public MembershipsPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/** The install's steps for the given installer (null for nobody), then the setup marker. */
	public void runSetup(Id installerId) {
		ShippedDefaultUpgrades.apply(
			MODULE_KEY,
			Memberships_Settings__c.SObjectType,
			SHIPPED_ON_ADDED_IN_UPGRADES
		);
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
