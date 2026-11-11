/**
 * What the BarnCRM Payments module does at install and at every upgrade (ADR-NEXT
 * `NEXT-payments-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Queue the job that gives the installer Payments Admin (a permission set assignment is a
 *    setup object write).
 * 2. Give the Payments sets to BarnCRM's roles (`PaymentsAccessSync`), queued for the same reason.
 *
 * Nothing is scheduled and no key is set at install: processing is scheduled from Health Check
 * and the keys are entered on Payments Setup, so a fresh install takes no payment.
 */
@NamespaceAccessible
public with sharing class PaymentsPostInstall implements InstallHandler, ModuleSetup {
	private static final String MODULE_KEY = 'Payments';
	@TestVisible
	private static final String ACCESS_CONTEXT = 'PaymentsPostInstall.grantInstallerAccess';

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
		if (installerId == null) {
			new PaymentsAccessSync().requestSync();
			return;
		}
		try {
			System.enqueueJob(new InstallerAccess(installerId));
		} catch (Exception e) {
			ErrorLogger.log(e, ACCESS_CONTEXT);
			new PaymentsAccessSync().requestSync();
		}
	}

	/**
	 * Gives the installer Payments Admin, unless they hold it already, then BarnCRM's roles their
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
				if (PaymentsAccessSync.syncOnce() && !Test.isRunningTest()) {
					System.enqueueJob(new ModuleAccessSyncBase.Job(new PaymentsAccessSync()));
				}
			} catch (Exception e) {
				ErrorLogger.log(e, ACCESS_CONTEXT);
			}
		}

		private void giveInstaller() {
			List<PermissionSet> sets = [
				SELECT Id
				FROM PermissionSet
				WHERE Name = :PaymentsAccessSync.ADMIN_SET AND IsOwnedByProfile = FALSE
				WITH SYSTEM_MODE
				LIMIT 1
			];
			if (
				sets.isEmpty() ||
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :installerId AND PermissionSetId = :sets[0].Id
					WITH SYSTEM_MODE
				] > 0
			) {
				return;
			}
			Database.SaveResult saved = Database.insert(
				new PermissionSetAssignment(AssigneeId = installerId, PermissionSetId = sets[0].Id),
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
