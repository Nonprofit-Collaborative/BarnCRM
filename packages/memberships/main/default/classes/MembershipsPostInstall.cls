/**
 * What the BarnCRM Memberships module does at install and at every upgrade (ADR-0206
 * `0206-memberships-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Turn on, once, a ship-on setting added in an upgrade (Core's `ShippedDefaultUpgrades`).
 * 2. Queue the job that gives the installer Memberships Admin (a permission set assignment is a
 *    setup object write).
 * 3. Give the Memberships sets to BarnCRM's roles (`MembershipsAccessSync`), queued for the same
 *    reason.
 *
 * Nothing else is set up: the nightly step joins Core's nightly run by itself, and reminders ship
 * off, so a fresh install emails nobody.
 */
@NamespaceAccessible
public with sharing class MembershipsPostInstall implements InstallHandler, ModuleSetup {
	private static final String MODULE_KEY = 'Memberships';
	@TestVisible
	private static final String ACCESS_CONTEXT = 'MembershipsPostInstall.grantInstallerAccess';

	/**
	 * Checkboxes that ship on, each turned on once in an org that saved the settings before it
	 * existed (QA-F2). Append only; `scripts/ci/check-setting-defaults.py` checks it.
	 */
	@TestVisible
	private static final List<Schema.SObjectField> SHIPPED_ON_ADDED_IN_UPGRADES = new List<Schema.SObjectField>{
		Memberships_Settings__c.Renew_From_Gifts__c
	};

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public MembershipsPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/** The install's steps for the given installer (null for nobody), then the setup marker. */
	public void runSetup(Id installerId) {
		ShippedDefaultUpgrades.apply(
			MODULE_KEY,
			Memberships_Settings__c.SObjectType,
			SHIPPED_ON_ADDED_IN_UPGRADES
		);
		ModuleSetups.markRan(MODULE_KEY);
		if (installerId == null) {
			new MembershipsAccessSync().requestSync();
			return;
		}
		try {
			System.enqueueJob(new InstallerAccess(installerId));
		} catch (Exception e) {
			ErrorLogger.log(e, ACCESS_CONTEXT);
			new MembershipsAccessSync().requestSync();
		}
	}

	/**
	 * Gives the installer Memberships Admin, unless they hold it already, then BarnCRM's roles their
	 * sets. System mode: the install runs as the platform's package user.
	 */
	public without sharing class InstallerAccess implements Queueable {
		private final Id installerId;

		public InstallerAccess(Id installerId) {
			this.installerId = installerId;
		}

		public void execute(QueueableContext jobContext) {
			try {
				giveInstaller();
				// A test cannot chain one queued job from another.
				if (MembershipsAccessSync.syncOnce() && !Test.isRunningTest()) {
					System.enqueueJob(new ModuleAccessSyncBase.Job(new MembershipsAccessSync()));
				}
			} catch (Exception e) {
				ErrorLogger.log(e, ACCESS_CONTEXT);
			}
		}

		private void giveInstaller() {
			PermissionSet permissionSet = SetupObjectSelector.permissionSet(
				MembershipsAccessSync.ADMIN_SET
			);
			if (
				permissionSet == null ||
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :installerId AND PermissionSetId = :permissionSet.Id
					WITH SYSTEM_MODE
				] > 0
			) {
				return;
			}
			Database.SaveResult saved = Database.insert(
				new PermissionSetAssignment(
					AssigneeId = installerId,
					PermissionSetId = permissionSet.Id
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
		}
	}
}
