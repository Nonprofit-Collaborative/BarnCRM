/**
 * What the BarnCRM Funders module does at install and at every upgrade (ADR-0161
 * `0161-funders-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Create the switch rows of the Automation page for the module's own automations (C-21),
 *    and copy in the shipped funder report templates the org does not have (F-06, R-FT3).
 *    A checkbox setting that ships on and was added in an upgrade is turned on once in an org
 *    that saved Funders Settings before it existed (QA-F2, `SHIPPED_ON_ADDED_IN_UPGRADES`).
 * 2. Queue the job that gives the installer the Funders Admin permission set. Queued because a
 *    permission set assignment is a setup object write, and this transaction has already written
 *    ordinary records (mixed DML).
 * 3. Give the Funders sets to BarnCRM's roles (`ModuleAccessSyncs`), queued for the same
 *    reason. The installer's job runs it after its own grant, so the two never insert the
 *    installer's Funders Admin at the same moment; with no installer it is queued alone.
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what
 * Finish Setup runs for a module copied into an org by hand (FS1, `ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class FundersPostInstall implements InstallHandler, ModuleSetup {
	/** The module's key in the module catalog and the setup marker. */
	public static final String MODULE_KEY = 'Funders';
	private static final String SWITCH_CONTEXT = 'FundersPostInstall.ensureAutomationSwitches';

	/**
	 * Funders checkboxes that ship on and were added in an upgrade, oldest first: each is turned
	 * on once in an org that saved Funders Settings before it existed (Core's
	 * `ShippedDefaultUpgrades`, QA-F2). Append only; `scripts/ci/check-setting-defaults.py`
	 * fails the build when a new ship-on checkbox is missing here.
	 */
	@TestVisible
	private static final List<Schema.SObjectField> SHIPPED_ON_ADDED_IN_UPGRADES = new List<Schema.SObjectField>{};

	/**
	 * Called by the platform after the module is installed or upgraded.
	 *
	 * @param context what the platform knows about this install
	 */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public FundersPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps (see the class comment), with the given person standing in for the
	 * installer, then the module's key added to the setup marker. Never throws.
	 *
	 * @param installerId the person to give Funders Admin, or null for nobody
	 */
	public void runSetup(Id installerId) {
		// Each entry point records its own failures and returns, so nothing here throws.
		AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
		FunderReportTemplates.installDefaultsDuringInstall();
		ShippedDefaultUpgrades.apply(
			MODULE_KEY,
			Funders_Settings__c.SObjectType,
			SHIPPED_ON_ADDED_IN_UPGRADES
		);
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
