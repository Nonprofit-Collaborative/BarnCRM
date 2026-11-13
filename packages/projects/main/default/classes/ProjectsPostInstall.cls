/**
 * What the BarnCRM Project Management module does at install and at every upgrade (ADR-0208
 * `0208-project-management-module.md`). Each step is safe to run twice and none can abort an
 * install, since every failure is written to the Error Log instead:
 *
 * 1. Turn on, once, a ship-on setting added in an upgrade (Core's `ShippedDefaultUpgrades`).
 * 2. Queue `ModuleAccessSyncs`, which gives Projects Admin to every BarnCRM Admin holder (the
 *    installer among them, given BarnCRM Admin by Core's own install) and the other sets to
 *    BarnCRM's roles. Queued, since a permission set assignment is a setup object write.
 * 3. Fill a blank Invoice payment return page with the org's My Domain address (`fillReturnUrl`).
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what Finish
 * Setup runs for a module copied into an org by hand (`ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class ProjectsPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'Projects';
	/**
	 * Checkboxes that ship on, each turned on once in an org that saved the settings before it
	 * existed (QA-F2). Append only; `scripts/ci/check-setting-defaults.py` checks it.
	 */
	@TestVisible
	private static final List<Schema.SObjectField> SHIPPED_ON_ADDED_IN_UPGRADES = new List<Schema.SObjectField>{};

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
		fillReturnUrl();
		ModuleSetups.markRan(MODULE_KEY);
		try {
			ModuleAccessSyncs.requestFor(MODULE_KEY);
		} catch (Exception e) {
			ErrorLogger.log(e, 'ProjectsPostInstall');
		}
	}

	/**
	 * Fills Invoice payment return page with the org's My Domain address while it is blank, so
	 * the settings console shows a changeable value, never a blank (PM-10). Written as the
	 * package's own bookkeeping, as `ShippedDefaultUpgrades` writes, since no person chose it.
	 */
	@TestVisible
	private static void fillReturnUrl() {
		try {
			SObject stored = OrgSettingsSystemWriter.lockStored(Projects_Settings__c.SObjectType);
			if (stored == null || String.isBlank((String) stored.get('Invoice_Return_Url__c'))) {
				OrgSettingsSystemWriter.save(
					Projects_Settings__c.SObjectType,
					new Map<Schema.SObjectField, Object>{
						Projects_Settings__c.Invoice_Return_Url__c => ProjectsSettings.myDomain()
					}
				);
			}
		} catch (Exception e) {
			ErrorLogger.log(e, 'ProjectsPostInstall');
		}
	}
}
