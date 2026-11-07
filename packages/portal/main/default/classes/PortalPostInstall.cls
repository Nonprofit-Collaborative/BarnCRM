/**
 * What the BarnCRM Portal Builder module does at install and at every upgrade (ADR-NEXT
 * `NEXT-portal-builder-off-platform-portal-api.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Queue the job that gives the installer Portal Builder Admin (a permission set assignment is
 *    a setup object write).
 * 2. Give the set to BarnCRM Admin holders (`PortalAccessSync`), queued for the same reason; the
 *    installer's job runs it after its own grant.
 *
 * Nothing is switched on: Portal Sign-In ships off, and no portal exists until an admin adds one.
 */
@NamespaceAccessible
public with sharing class PortalPostInstall implements InstallHandler, ModuleSetup {
	private static final String MODULE_KEY = 'Portal';
	@TestVisible
	private static final String ACCESS_CONTEXT = 'PortalPostInstall.grantInstallerAccess';

	/** Called by the platform after the module is installed or upgraded. */
	public void onInstall(InstallContext context) {
		if (context == null) {
			return;
		}
		runSetup(context.installerId());
	}

	/** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
	@NamespaceAccessible
	public PortalPostInstall() {
		// Nothing to set up: every step runs in runSetup.
	}

	/**
	 * The install's steps, with the given person standing in for the installer, then the module's
	 * key added to the setup marker. Never throws.
	 */
	public void runSetup(Id installerId) {
		ModuleSetups.markRan(MODULE_KEY);
		if (installerId == null) {
			new PortalAccessSync().requestSync();
			return;
		}
		try {
			System.enqueueJob(new InstallerAccess(installerId));
		} catch (Exception e) {
			ErrorLogger.log(e, ACCESS_CONTEXT);
			new PortalAccessSync().requestSync();
		}
	}

	/**
	 * Gives the installer Portal Builder Admin, unless they hold it already, then BarnCRM Admin
	 * holders theirs. System mode: the install runs as the platform's package user.
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
				if (PortalAccessSync.syncOnce() && !Test.isRunningTest()) {
					System.enqueueJob(new ModuleAccessSyncBase.Job(new PortalAccessSync()));
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
					WHERE Name = :PortalAccessSync.ADMIN_SET AND IsOwnedByProfile = FALSE
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
