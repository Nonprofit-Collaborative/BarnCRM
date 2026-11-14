/**
 * What the BarnCRM Event Management module does at install and at every upgrade (ADR-0177
 * `0177-events-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Create the switch rows of the Automation page for the module's own automations (C-21).
 * 2. Queue the job that gives the installer the Events Admin permission set. Queued because a
 *    permission set assignment is a setup object write, and this transaction has already written
 *    ordinary records (mixed DML).
 * 3. Give the Event Management sets to BarnCRM's roles (`ModuleAccessSyncs`), queued for the same
 *    reason. The installer's job runs it after its own grant; with no installer it is queued
 *    alone.
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what
 * Finish Setup runs for a module copied into an org by hand (FS1, `ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class EventsPostInstall implements InstallHandler, ModuleSetup {
	/** The module's key in the module catalog and the setup marker. */
	public static final String MODULE_KEY = 'Events';
	private static final String SWITCH_CONTEXT = 'EventsPostInstall.ensureAutomationSwitches';

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
	public EventsPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps (see the class comment), with the given person standing in for the
	 * installer, then the module's key added to the setup marker. Never throws.
	 *
	 * @param installerId the person to give Events Admin, or null for nobody
	 */
	public void runSetup(Id installerId) {
		// Each entry point records its own failures and returns, so nothing here throws.
		AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
