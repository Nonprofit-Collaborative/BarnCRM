/**
 * The Gift Transaction mirror page (feature X-07, R-GT6, R-GT10): says whether the mirror can
 * work in this org and for this person, starts Run Now, schedules and stops the nightly run,
 * compares a range, and copies a range again. Every refusal is in words the page shows as they
 * are. It returns plain values only, so the page's logic stays in its framework-free module.
 */
public with sharing class GiftTransactionMirrorController {
	private static final String CONTEXT = 'GiftTransactionMirrorController';
	/**
	 * Held through the Gift Transaction Mirror permission set. Reading the page's status and the
	 * reconciliation needs it, as the page's entry in the settings console does (ADR-0038).
	 */
	private static final String USE_PERMISSION = 'Use_Gift_Transaction_Mirror';

	/** What the page shows. */
	public class Status {
		@AuraEnabled
		public Boolean available;
		@AuraEnabled
		public String direction;
		@AuraEnabled
		public String paidStatus;
		@AuraEnabled
		public Date startDate;
		/** Why nothing is copied yet, in words, or null when the mirror is ready (R-GT2). */
		@AuraEnabled
		public String notReadyReason;
		@AuraEnabled
		public Boolean canRun;
		@AuraEnabled
		public Boolean canManage;
		@AuraEnabled
		public Boolean running;
		@AuraEnabled
		public Datetime nextRunAt;
		/** When the last completed run started, and what it did (ADR-0038 point 4). */
		@AuraEnabled
		public Datetime lastRunAt;
		@AuraEnabled
		public String lastSummary;
	}

	@AuraEnabled
	public static Status getStatus() {
		requireUse();
		try {
			return status();
		} catch (Exception unexpected) {
			throw failed(unexpected);
		}
	}

	/** Starts a run, or says in words why it cannot start. */
	@AuraEnabled
	public static Status runNow() {
		Status current = checked(false);
		try {
			GiftTransactionMirrorBatch.run();
		} catch (Exception unexpected) {
			throw failed(unexpected);
		}
		current.running = true;
		return current;
	}

	/** Copies again every gift of R-GT3 dated in the range. */
	@AuraEnabled
	public static Status copyRangeAgain(Date fromDate, Date toDate) {
		Status current = checked(false);
		if (fromDate == null || toDate == null) {
			throw UserErrors.message(
				BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_ErrorDatesRequired')
			);
		}
		if (fromDate > toDate) {
			throw UserErrors.message(
				BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_ErrorDateOrder')
			);
		}
		try {
			GiftTransactionMirrorBatch.runRange(fromDate, toDate);
		} catch (Exception unexpected) {
			throw failed(unexpected);
		}
		current.running = true;
		return current;
	}

	/** Schedules the nightly run at 01:35, as the person clicking (ADR-0038). */
	@AuraEnabled
	public static Status schedule() {
		checked(true);
		try {
			GiftTransactionMirrorSchedulable.schedule();
			return status();
		} catch (Exception unexpected) {
			throw failed(unexpected);
		}
	}

	@AuraEnabled
	public static Status stop() {
		requireUse();
		Status current = status();
		if (!current.canManage) {
			throw UserErrors.message(
				BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_NoManagePermission')
			);
		}
		try {
			GiftTransactionMirrorSchedulable.stop();
			return status();
		} catch (Exception unexpected) {
			throw failed(unexpected);
		}
	}

	/** The reconciliation for a range, as the person viewing can see it (R-GT10). */
	@AuraEnabled
	public static GiftTransactionMirrorReconciliation.Comparison compare(
		Date fromDate,
		Date toDate
	) {
		requireUse();
		try {
			return GiftTransactionMirrorReconciliation.compare(fromDate, toDate);
		} catch (GiftTransactionMirrorReconciliation.ReconciliationException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (Exception unexpected) {
			throw failed(unexpected);
		}
	}

	private static void requireUse() {
		if (!FeatureManagement.checkPermission(USE_PERMISSION)) {
			throw UserErrors.message(Label.Mirror_GiftTransactionMirror_NoUsePermission);
		}
	}

	/** The current status when a run may start, or the refusal in words. */
	private static Status checked(Boolean scheduling) {
		requireUse();
		Status current;
		try {
			current = status();
		} catch (Exception unexpected) {
			throw failed(unexpected);
		}
		String refusal = refusal(current, scheduling);
		if (refusal != null) {
			throw UserErrors.message(refusal);
		}
		return current;
	}

	@TestVisible
	private static String refusal(Status current, Boolean scheduling) {
		if (!current.available) {
			return Label.Mirror_GiftTransactionMirror_Unavailable;
		}
		if (current.direction == GiftTransactionMirrorService.OFF) {
			return Label.Mirror_GiftTransactionMirror_SwitchedOff;
		}
		if (!current.canManage) {
			return BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_NoManagePermission');
		}
		if (current.notReadyReason != null) {
			return current.notReadyReason;
		}
		if (!current.canRun) {
			return Label.Mirror_GiftTransactionMirror_NoAccess;
		}
		if (current.running && !scheduling) {
			return BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_Running');
		}
		return null;
	}

	private static Status status() {
		Status current = new Status();
		current.available = GiftTransactionMirrorService.isAvailable();
		current.direction = GiftTransactionMirrorService.direction();
		current.paidStatus = GiftTransactionMirrorService.paidStatus();
		current.startDate = GiftTransactionMirrorService.startDate();
		current.notReadyReason = current.available
			? GiftTransactionMirrorService.notReadyReason()
			: null;
		current.canManage = AutomationControl.canManage();
		current.canRun = GiftTransactionMirrorService.canRun();
		current.running = GiftTransactionMirrorSchedulable.isRunning();
		current.nextRunAt = GiftTransactionMirrorSchedulable.nextRunAt();
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		current.lastRunAt = settings?.Gift_Transaction_Mirror_Last_Run__c;
		current.lastSummary = settings?.Gift_Transaction_Mirror_Last_Summary__c;
		return current;
	}

	private static AuraHandledException failed(Exception unexpected) {
		ErrorLogger.log(unexpected, CONTEXT);
		// The shared Mirror page wording, kept once to stay within the org's custom label limit.
		return UserErrors.message(BarnHelp.text('Mirror', 'Mirror_OpportunityMirror_ErrorFailed'));
	}
}
