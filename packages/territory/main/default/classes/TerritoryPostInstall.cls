/**
 * What the BarnCRM Territory Management module does at install and at every upgrade (ADR-0205
 * `0205-territory-management-module.md`). Nothing here changes a record: territories are the
 * admin's, and the nightly step ships off.
 *
 * 1. Add the module to Core's setup marker (`ModuleSetups`), which Finish Setup also runs.
 * 2. Queue the job that gives the installer Territory Admin (a permission set assignment is a
 *    setup object write), which then gives BarnCRM's roles their sets
 *    (`TerritoryAccessSync`). Every failure goes to the Error Log; none can abort an install.
 */
@NamespaceAccessible
public with sharing class TerritoryPostInstall implements InstallHandler, ModuleSetup {
	private static final String MODULE_KEY = 'Territory';
	@TestVisible
	private static final String ACCESS_CONTEXT = 'TerritoryPostInstall.grantInstallerAccess';

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public TerritoryPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/** The install's steps, with the given person standing in for the installer. Never throws. */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
		if (installerId == null) {
			new TerritoryAccessSync().requestSync();
			return;
		}
		try {
			System.enqueueJob(new InstallerAccess(installerId));
		} catch (Exception e) {
			ErrorLogger.log(e, ACCESS_CONTEXT);
			new TerritoryAccessSync().requestSync();
		}
	}

	/**
	 * Gives the installer Territory Admin, unless they hold it already, then BarnCRM's roles
	 * their sets. System mode: the install runs as the platform's package user.
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
				if (TerritoryAccessSync.syncOnce() && !Test.isRunningTest()) {
					System.enqueueJob(new ModuleAccessSyncBase.Job(new TerritoryAccessSync()));
				}
			} catch (Exception e) {
				ErrorLogger.log(e, ACCESS_CONTEXT);
			}
		}

		private void giveInstaller() {
			try {
				PermissionSet permissionSet = SetupObjectSelector.permissionSet(
					TerritoryAccessSync.ADMIN_SET
				);
				if (permissionSet == null) {
					return;
				}
				Integer held = [
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :installerId AND PermissionSetId = :permissionSet.Id
					WITH SYSTEM_MODE
				];
				if (held > 0) {
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
			} catch (Exception e) {
				ErrorLogger.log(e, ACCESS_CONTEXT);
			}
		}
	}
}
