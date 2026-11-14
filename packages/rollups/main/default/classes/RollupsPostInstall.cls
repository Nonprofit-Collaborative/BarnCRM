/**
 * What the BarnCRM Rollup Builder module does at install and at every upgrade (ADR-0125
 * `0125-rollup-builder-module.md`, decision 5).
 *
 * Five things, each safe to run twice and none able to abort an install, since every failure
 * is written to the Error Log instead:
 *
 * 1. Give an org that has no module settings row one holding the shipped defaults (a new
 *    rollup starts in Both, real-time totals are recalculated just after the save), so the
 *    Settings console and every reader of the settings find a row. A row that exists is never
 *    touched.
 * 2. Create the shipped Rollup Definitions this org does not have yet, so a fresh org has its
 *    totals without anybody pressing a button, and leave every definition already here exactly
 *    as the administrator left it (R-R6, ADR-0029). The module sees only the shipped defaults
 *    whose source and target are in the org; Giving makes the same call from its own script.
 * 3. Create the switch rows of the Automation page for the module's own automations (C-21).
 * 4. Queue the job that gives the installer the Rollup Builder Admin permission set. Queued
 *    because a permission set assignment is a setup object write, and this transaction has
 *    already written ordinary records (mixed DML).
 * 5. Give the Rollup Builder sets to BarnCRM's roles (`ModuleAccessSyncs`, D2), queued for the
 *    same reason. The installer's job runs it after its own grant, so the two never insert the
 *    installer's Rollup Builder Admin at the same moment; with no installer it is queued alone.
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what
 * Finish Setup runs for a module copied into an org by hand (FS1, `ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class RollupsPostInstall implements InstallHandler, ModuleSetup {
	/** The module's key in the module catalog and the setup marker. */
	private static final String MODULE_KEY = 'Rollups';

	@TestVisible
	private static final String ROLLUP_CONTEXT = 'RollupsPostInstall.ensureRollupDefaults';
	private static final String SWITCH_CONTEXT = 'RollupsPostInstall.ensureAutomationSwitches';
	@TestVisible
	private static final String SETTINGS_CONTEXT = 'RollupsPostInstall.ensureSettingsRow';

	/** The permission set the installer is given. */
	public static final String ADMIN_PERMISSION_SET = 'Rollup_Builder_Admin';

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
	public RollupsPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps (see the class comment), with the given person standing in for the
	 * installer, then the module's key added to the setup marker. Never throws.
	 *
	 * @param installerId the person to give Rollup Builder Admin, or null for nobody
	 */
	public void runSetup(Id installerId) {
		// The entry points record their own failures and return, so nothing here throws.
		ensureSettingsRow();
		RollupService.ensureDefaultsDuringInstall(ROLLUP_CONTEXT);
		AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}

	/**
	 * Creates the org-level Rollup Settings row with the shipped defaults when the org has none,
	 * so a new or source-deployed org shows Default Rollup Mode Both and Rollup Processing
	 * Background instead of two empty pickers. Does nothing when a row exists, whatever it
	 * holds, so no saved value is ever overwritten. Written in system mode with no audit row:
	 * it records the shipped state, not a change anybody made. Also run by
	 * `scripts/org/deploy-packages.sh`. Never throws: a failure goes to the Error Log.
	 */
	public static void ensureSettingsRow() {
		try {
			if (Rollup_Settings__c.getOrgDefaults().Id != null) {
				return;
			}
			Database.insert(
				new Rollup_Settings__c(
					SetupOwnerId = UserInfo.getOrganizationId(),
					Rollup_Mode_Default__c = RollupService.MODE_BOTH,
					Rollup_Processing__c = RollupService.PROCESSING_BACKGROUND
				),
				AccessLevel.SYSTEM_MODE
			);
			SettingsService.clearCaches();
		} catch (Exception e) {
			ErrorLogger.log(e, SETTINGS_CONTEXT);
		}
	}
}
