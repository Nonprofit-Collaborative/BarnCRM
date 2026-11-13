/**
 * What the BarnCRM Contact Point Sync module does at install and at every upgrade (ADR-0176
 * contact point sync module).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Create the switch rows of the Automation page for the module's two automations.
 * 2. Queue the job that gives the installer Contact Point Sync Admin (a permission set assignment
 *    is a setup object write, and this transaction has already written ordinary records).
 * 3. Give the set to BarnCRM Admin holders (`ModuleAccessSyncs`), queued for the same
 *    reason; the installer's job runs it after its own grant.
 *
 * Nothing is copied at install: the admin previews and starts the backfill on the Contact Point
 * Sync page (decision 10).
 */
@NamespaceAccessible
public with sharing class ContactPointsPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'ContactPoints';
	private static final String SWITCH_CONTEXT = 'ContactPointsPostInstall.ensureAutomationSwitches';

	/**
	 * Checkboxes that ship on, each turned on once in an org that saved the settings before it
	 * existed (Core's `ShippedDefaultUpgrades`, QA-F2). Append only;
	 * `scripts/ci/check-setting-defaults.py` fails the build when one is missing.
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
	public ContactPointsPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps, with the given person standing in for the installer, then the module's
	 * key added to the setup marker. Never throws.
	 */
	public void runSetup(Id installerId) {
		AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
		ShippedDefaultUpgrades.apply(
			MODULE_KEY,
			Contact_Point_Sync_Settings__c.SObjectType,
			SHIPPED_ON_ADDED_IN_UPGRADES
		);
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
