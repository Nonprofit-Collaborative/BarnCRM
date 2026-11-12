/**
 * What the BarnCRM Project Management module does at install and at every upgrade (ADR-0208
 * `0208-project-management-module.md`). Each step is safe to run twice and none can abort an
 * install, since every failure is written to the Error Log instead:
 *
 * 1. Turn on, once, a ship-on setting added in an upgrade (Core's `ShippedDefaultUpgrades`).
 * 2. Queue `ProjectsAccessSync`, which gives Projects Admin to every BarnCRM Admin holder (the
 *    installer among them, given BarnCRM Admin by Core's own install) and the other sets to
 *    BarnCRM's roles. Queued, since a permission set assignment is a setup object write.
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what Finish
 * Setup runs for a module copied into an org by hand (`ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class ProjectsPostInstall implements InstallHandler, ModuleSetup {
	private static final String MODULE_KEY = 'Projects';
	/**
	 * Checkboxes that ship on, each turned on once in an org that saved the settings before it
	 * existed (QA-F2). Append only; `scripts/ci/check-setting-defaults.py` checks it.
	 */
	@TestVisible
	private static final List<Schema.SObjectField> SHIPPED_ON_ADDED_IN_UPGRADES = new List<Schema.SObjectField>{
		Projects_Settings__c.Time_Tracking_Enabled__c
	};

	@NamespaceAccessible
	public ProjectsPostInstall() {
		// Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor.
	}

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context != null) {
			runSetup(context.installerId());
		}
	}

	/** The install's steps, then the module's key added to the setup marker. Never throws. */
	public void runSetup(Id installerId) {
		ShippedDefaultUpgrades.apply(
			MODULE_KEY,
			Projects_Settings__c.SObjectType,
			SHIPPED_ON_ADDED_IN_UPGRADES
		);
		ModuleSetups.markRan(MODULE_KEY);
		try {
			new ProjectsAccessSync().requestSync();
		} catch (Exception e) {
			ErrorLogger.log(e, 'ProjectsPostInstall');
		}
	}
}
