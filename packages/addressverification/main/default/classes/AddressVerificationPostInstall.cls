/**
 * What the BarnCRM Address Verification module does at install and at every upgrade (ADR-0209
 * `0209-address-verification-module.md`). Safe to run twice; a failure is logged, never raised:
 * the installer gets Address Verification Admin, then BarnCRM Admin holders do
 * (`ModuleAccessSyncs`), both queued because an assignment is a setup object write.
 *
 * No key is set at install and nothing is looked up until the keys are entered on Address
 * Verification Setup.
 */
@NamespaceAccessible
public with sharing class AddressVerificationPostInstall implements InstallHandler, ModuleSetup {
	private static final String SWITCH_CONTEXT = 'AddressVerificationPostInstall.ensureAutomationSwitches';

	/**
	 * Checkboxes that ship on, each turned on once in an org that saved the settings before it
	 * existed (Core's `ShippedDefaultUpgrades`, QA-F2). Append only;
	 * `scripts/ci/check-setting-defaults.py` fails the build when one is missing.
	 */
	@TestVisible
	private static final List<Schema.SObjectField> SHIPPED_ON_ADDED_IN_UPGRADES = new List<Schema.SObjectField>{};

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
		ShippedDefaultUpgrades.apply(
			AddressVerifier.MODULE,
			Address_Verification_Settings__c.SObjectType,
			SHIPPED_ON_ADDED_IN_UPGRADES
		);
		ModuleSetups.markRan(AddressVerifier.MODULE);
		ModuleAccessSyncs.setUp(AddressVerifier.MODULE, installerId);
	}
}
