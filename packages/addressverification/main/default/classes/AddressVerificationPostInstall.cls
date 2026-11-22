/**
 * What the BarnCRM Address Verification module does at install and at every upgrade (ADR-0209
 * `0209-address-verification-module.md`). Safe to run twice; a failure is logged, never raised:
 * the installer gets Address Verification Admin, then BarnCRM Admin holders do
 * (`ModuleAccessSyncs`), both queued because an assignment is a setup object write.
 *
 * No key is shipped and nothing is looked up until the provider's key is entered on its External
 * Credential in Setup and Check Connection succeeds on Address Verification Setup (R-AV4).
 */
@NamespaceAccessible
public with sharing class AddressVerificationPostInstall implements InstallHandler, ModuleSetup {
	private static final String SWITCH_CONTEXT = 'AddressVerificationPostInstall.ensureAutomationSwitches';

	public void onInstall(InstallContext context) {
		if (context != null) {
			runSetup(context.installerId());
		}
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public AddressVerificationPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	public void runSetup(Id installerId) {
		AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
		ModuleSetups.markRan(AddressVerifier.MODULE);
		ModuleAccessSyncs.setUp(AddressVerifier.MODULE, installerId);
	}
}
