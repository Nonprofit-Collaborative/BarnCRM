/**
 * What the BarnCRM Address Verification module does at install and at every upgrade (ADR-NEXT
 * `NEXT-address-verification-module.md`). Safe to run twice; a failure is logged, never raised:
 * the installer gets Address Verification Admin, then BarnCRM Admin holders do
 * (`AddressVerificationAccessSync`), both queued because an assignment is a setup object write.
 *
 * No key is set at install and nothing is looked up until the keys are entered on Address
 * Verification Setup.
 */
@NamespaceAccessible
public with sharing class AddressVerificationPostInstall implements InstallHandler, ModuleSetup {
	@TestVisible
	private static final String ACCESS_CONTEXT = 'AddressVerificationPostInstall.grantInstallerAccess';
	private static final String SWITCH_CONTEXT = 'AddressVerificationPostInstall.ensureAutomationSwitches';

	/**
	 * Checkboxes that ship on, each turned on once in an org that saved the settings before it
	 * existed (Core's `ShippedDefaultUpgrades`, QA-F2). Append only;
	 * `scripts/ci/check-setting-defaults.py` fails the build when one is missing.
	 */
	@TestVisible
	private static final List<Schema.SObjectField> SHIPPED_ON_ADDED_IN_UPGRADES = new List<Schema.SObjectField>{
		Address_Verification_Settings__c.Verify_On_Save__c
	};

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
		if (installerId == null) {
			new AddressVerificationAccessSync().requestSync();
			return;
		}
		try {
			System.enqueueJob(new InstallerAccess(installerId));
		} catch (Exception e) {
			ErrorLogger.log(e, ACCESS_CONTEXT);
			new AddressVerificationAccessSync().requestSync();
		}
	}

	/** Gives the installer the admin set, then BarnCRM Admin holders. System mode: the install user. */
	public without sharing class InstallerAccess implements Queueable {
		private final Id installerId;

		public InstallerAccess(Id installerId) {
			this.installerId = installerId;
		}

		public void execute(QueueableContext jobContext) {
			try {
				List<PermissionSet> sets = [
					SELECT Id
					FROM PermissionSet
					WHERE
						Name = :AddressVerificationAccessSync.ADMIN_SET
						AND IsOwnedByProfile = FALSE
					WITH SYSTEM_MODE
					LIMIT 1
				];
				Database.SaveResult saved = sets.isEmpty()
					? null
					: Database.insert(
							new PermissionSetAssignment(
								AssigneeId = installerId,
								PermissionSetId = sets[0].Id
							),
							false,
							AccessLevel.SYSTEM_MODE
					  );
				// A duplicate means it is held already: what was wanted.
				for (
					Database.Error error : saved == null
						? new List<Database.Error>()
						: saved.getErrors()
				) {
					if (error.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
						ErrorLogger.logMessage(
							error.getMessage(),
							ACCESS_CONTEXT,
							ErrorLogger.SEVERITY_WARNING
						);
					}
				}
				AddressVerificationAccessSync.syncOnce();
			} catch (Exception e) {
				ErrorLogger.log(e, ACCESS_CONTEXT);
			}
		}
	}
}
