/**
 * What the BarnCRM Rollup Builder module does at install and at every upgrade (ADR-0125
 * `0125-rollup-builder-module.md`, decision 5).
 *
 * Five things, each safe to run twice and none able to abort an install, since every failure
 * is written to the Error Log instead:
 *
 * 1. Create the module's run-state rows, the run lock among them, when the org lacks them. A
 *    row that exists is never touched.
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

	/** The module's run-state rows, created at install so two first runs never each make one. */
	@TestVisible
	private static final List<String> STATE_NAMES = new List<String>{
		'Last_Run_Started__c',
		'Nightly_Covered_From__c',
		'Processor_Requested_At__c'
	};

	/**
	 * Creates the module's run-state rows when the org lacks them: the run lock
	 * (`Rollups.Last_Run_Started__c`, which `RollupLargeParentBatch` locks), the nightly
	 * watermark and the processor stamp, each holding what the org had (its legacy value until
	 * carry-over), so a row that exists is never changed. The settings themselves need nothing:
	 * an unsaved setting reads its shipped default (ADR-NEXT settings as custom metadata). Also
	 * run by `scripts/org/deploy-packages.sh`. Never throws: a failure goes to the Error Log.
	 */
	public static void ensureSettingsRow() {
		try {
			for (String name : STATE_NAMES) {
				SettingsState.lockOrCreate(RollupService.stateKey(name));
			}
		} catch (Exception e) {
			ErrorLogger.log(e, SETTINGS_CONTEXT);
		}
	}
}
