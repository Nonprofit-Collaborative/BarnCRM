/**
 * What the BarnCRM Contact Point Sync module does at install and at every upgrade (ADR-0176
 * contact point sync module).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Create the switch rows of the Automation page for the module's two automations.
 * 2. Queue the job that gives the installer Contact Point Sync Admin (a permission set assignment
 *    is a setup object write, and this transaction has already written ordinary records).
 * 3. Give the set to BarnCRM Admin holders (`ContactPointsAccessSync`), queued for the same
 *    reason; the installer's job runs it after its own grant.
 *
 * Nothing is copied at install: the admin previews and starts the backfill on the Contact Point
 * Sync page (decision 10).
 */
@NamespaceAccessible
public with sharing class ContactPointsPostInstall implements InstallHandler, ModuleSetup {
	private static final String MODULE_KEY = 'ContactPoints';
	private static final String SWITCH_CONTEXT = 'ContactPointsPostInstall.ensureAutomationSwitches';
	@TestVisible
	private static final String ACCESS_CONTEXT = 'ContactPointsPostInstall.grantInstallerAccess';

	/**
	 * Checkboxes that ship on, each turned on once in an org that saved the settings before it
	 * existed (Core's `ShippedDefaultUpgrades`, QA-F2). Append only;
	 * `scripts/ci/check-setting-defaults.py` fails the build when one is missing.
	 */
	@TestVisible
	private static final List<Schema.SObjectField> SHIPPED_ON_ADDED_IN_UPGRADES = new List<Schema.SObjectField>{};

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public ContactPointsPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps, with the given person standing in for the installer, then the module's
	 * key added to the setup marker. Never throws.
	 */
	public void runSetup(Id installerId) {
		AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
		ShippedDefaultUpgrades.apply(
			MODULE_KEY,
			Contact_Point_Sync_Settings__c.SObjectType,
			SHIPPED_ON_ADDED_IN_UPGRADES
		);
		ModuleSetups.markRan(MODULE_KEY);
		if (installerId == null) {
			new ContactPointsAccessSync().requestSync();
			return;
		}
		try {
			System.enqueueJob(new InstallerAccess(installerId));
		} catch (Exception e) {
			ErrorLogger.log(e, ACCESS_CONTEXT);
			new ContactPointsAccessSync().requestSync();
		}
	}

	/**
	 * Gives the installer Contact Point Sync Admin, unless they hold it already, then BarnCRM
	 * Admin holders theirs. System mode: the install runs as the platform's package user.
	 */
	public without sharing class InstallerAccess implements Queueable {
		private final Id installerId;

		public InstallerAccess(Id installerId) {
			this.installerId = installerId;
		}

		public void execute(QueueableContext jobContext) {
			giveInstaller();
			try {
				// A test cannot chain one queued job from another.
				if (ContactPointsAccessSync.syncOnce() && !Test.isRunningTest()) {
					System.enqueueJob(new ModuleAccessSyncBase.Job(new ContactPointsAccessSync()));
				}
			} catch (Exception e) {
				ErrorLogger.log(e, ACCESS_CONTEXT);
			}
		}

		private void giveInstaller() {
			try {
				List<PermissionSet> sets = [
					SELECT Id
					FROM PermissionSet
					WHERE Name = :ContactPointsAccessSync.ADMIN_SET AND IsOwnedByProfile = FALSE
					WITH SYSTEM_MODE
					LIMIT 1
				];
				if (sets.isEmpty()) {
					return;
				}
				Integer held = [
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :installerId AND PermissionSetId = :sets[0].Id
					WITH SYSTEM_MODE
				];
				if (held > 0) {
					return;
				}
				Database.SaveResult saved = Database.insert(
					new PermissionSetAssignment(
						AssigneeId = installerId,
						PermissionSetId = sets[0].Id
					),
					false,
					AccessLevel.SYSTEM_MODE
				);
				// A duplicate means another job gave it a moment before: what was wanted.
				for (Database.Error error : saved.getErrors()) {
					if (error.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
						ErrorLogger.logMessage(
							error.getMessage(),
							ACCESS_CONTEXT,
							ErrorLogger.SEVERITY_WARNING
						);
					}
				}
			} catch (Exception e) {
				ErrorLogger.log(e, ACCESS_CONTEXT);
			}
		}
	}
}
