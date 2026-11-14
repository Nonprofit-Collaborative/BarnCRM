/**
 * What the BarnCRM Payments module does at install and at every upgrade (ADR-0201
 * `0201-payments-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Queue the job that gives the installer Payments Admin (a permission set assignment is a
 *    setup object write).
 * 2. Give the Payments sets to BarnCRM's roles (`ModuleAccessSyncs`), queued for the same reason.
 *
 * Nothing is scheduled and no key is set at install: processing is scheduled from Health Check
 * and the keys are entered on Payments Setup, so a fresh install takes no payment.
 */
@NamespaceAccessible
public with sharing class PaymentsPostInstall implements InstallHandler, ModuleSetup {
	public static final String MODULE_KEY = 'Payments';

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public PaymentsPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/** The install's steps for the given installer (null for nobody), then the setup marker. */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
		ModuleAccessSyncs.setUp(MODULE_KEY, installerId);
	}
}
