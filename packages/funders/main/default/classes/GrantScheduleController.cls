/**
 * The Award Schedule card on a grant's page (F-05, canonical model 29ZM, ADR-0162
 * `0162-funders-restricted-funds-schedules-calendar.md` decision 6): the grant's payments and
 * totals, building a schedule, and marking a payment received.
 *
 * Thin by design (plan Section 9.9): plain shapes out, the split in the browser module
 * `grantScheduleModel`, the rules in `GrantPaymentService`. Everything runs as the person.
 */
public with sharing class GrantScheduleController {
	private static final String CONTEXT = 'GrantScheduleController';

	/** What the card draws. */
	public class Schedule {
		@AuraEnabled
		public String stage;
		@AuraEnabled
		public Decimal amountAwarded;
		@AuraEnabled
		public Date startDate;
		@AuraEnabled
		public Date endDate;
		@AuraEnabled
		public Decimal amountScheduled = 0;
		@AuraEnabled
		public Decimal amountReceived = 0;
		@AuraEnabled
		public List<Payment> payments = new List<Payment>();
		/** R-GP2: a schedule can be built here, and the person can create payments. */
		@AuraEnabled
		public Boolean canBuild = false;
		/** The person can mark a payment received. */
		@AuraEnabled
		public Boolean canMarkReceived = false;
		/** The grant's Payment Frequency, if any. */
		@AuraEnabled
		public String frequency;
		/** The Payment Frequency choices, as the org labels them. */
		@AuraEnabled
		public List<Option> frequencies = new List<Option>();
		/** The card's headings, from the field labels, so the platform translates them. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One choice. */
	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;

		public Option(String label, String value) {
			this.label = label;
			this.value = value;
		}
	}

	/** One payment. */
	public class Payment {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Date dueDate;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Date receivedDate;
	}

	/** The card for one grant. */
	@AuraEnabled
	public static Schedule getSchedule(Id grantId) {
		try {
			Schedule schedule = new Schedule();
			addLabels(schedule);
			List<Grant__c> grants = [
				SELECT
					Id,
					Stage__c,
					Payment_Frequency__c,
					Amount_Awarded__c,
					Award_Start_Date__c,
					Award_End_Date__c,
					Amount_Scheduled__c,
					Amount_Received__c,
					(
						SELECT Id, Name, Due_Date__c, Amount__c, Status__c, Received_Date__c
						FROM Payments__r
						ORDER BY Due_Date__c, Name
						LIMIT :GrantPaymentService.MAX_PAYMENTS
					)
				FROM Grant__c
				WHERE Id = :grantId
				WITH USER_MODE
				LIMIT 1
			];
			if (grants.isEmpty()) {
				return schedule;
			}
			Grant__c grant = grants[0];
			schedule.stage = grant.Stage__c;
			schedule.frequency = grant.Payment_Frequency__c;
			schedule.amountAwarded = grant.Amount_Awarded__c;
			schedule.startDate = grant.Award_Start_Date__c;
			schedule.endDate = grant.Award_End_Date__c;
			schedule.amountScheduled = grant.Amount_Scheduled__c == null
				? 0
				: grant.Amount_Scheduled__c;
			schedule.amountReceived = grant.Amount_Received__c == null
				? 0
				: grant.Amount_Received__c;
			Integer live = 0;
			for (Grant_Payment__c row : grant.Payments__r) {
				Payment payment = new Payment();
				payment.id = row.Id;
				payment.name = row.Name;
				payment.dueDate = row.Due_Date__c;
				payment.amount = row.Amount__c;
				payment.status = row.Status__c;
				payment.receivedDate = row.Received_Date__c;
				schedule.payments.add(payment);
				if (GrantPaymentService.LIVE_STATUSES.contains(row.Status__c)) {
					live++;
				}
			}
			schedule.canBuild =
				Schema.SObjectType.Grant_Payment__c.isCreateable() &&
				GrantPaymentService.canBuild(grant, live);
			schedule.canMarkReceived = Schema.SObjectType.Grant_Payment__c.isUpdateable();
			return schedule;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getSchedule', grantId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Schedule_LoadFailed'));
		}
	}

	/** Field labels for the headings and the Payment Frequency choices, by describe. */
	private static void addLabels(Schedule schedule) {
		Map<String, String> grantFields = new Map<String, String>{
			'awarded' => 'Amount_Awarded__c',
			'scheduled' => 'Amount_Scheduled__c',
			'received' => 'Amount_Received__c',
			'frequency' => 'Payment_Frequency__c',
			'startDate' => 'Award_Start_Date__c',
			'endDate' => 'Award_End_Date__c'
		};
		Map<String, String> paymentFields = new Map<String, String>{
			'dueDate' => 'Due_Date__c',
			'amount' => 'Amount__c',
			'status' => 'Status__c',
			'receivedDate' => 'Received_Date__c'
		};
		for (String key : grantFields.keySet()) {
			schedule.fieldLabels.put(
				key,
				NamespaceUtil.fieldLabel(Grant__c.SObjectType, grantFields.get(key))
			);
		}
		for (String key : paymentFields.keySet()) {
			schedule.fieldLabels.put(
				key,
				NamespaceUtil.fieldLabel(Grant_Payment__c.SObjectType, paymentFields.get(key))
			);
		}
		for (
			Schema.PicklistEntry entry : Grant__c.Payment_Frequency__c.getDescribe()
				.getPicklistValues()
		) {
			if (entry.isActive()) {
				schedule.frequencies.add(new Option(entry.getLabel(), entry.getValue()));
			}
		}
	}

	/**
	 * Saves a built schedule (R-GP2) and the frequency it was split at.
	 *
	 * @param grantId the grant
	 * @param frequency the Payment Frequency value the rows were split at
	 * @param paymentsJson the rows, as `[{"dueDate": "2027-01-01", "amount": 12500}]`
	 */
	@AuraEnabled
	public static void saveSchedule(Id grantId, String frequency, String paymentsJson) {
		if (!Schema.SObjectType.Grant_Payment__c.isCreateable()) {
			throw UserErrors.message(
				BarnHelp.text('Funders', 'Funders_Pipeline_ErrorNoPermission')
			);
		}
		List<GrantPaymentService.Row> rows;
		try {
			rows = (List<GrantPaymentService.Row>) JSON.deserialize(
				paymentsJson,
				List<GrantPaymentService.Row>.class
			);
		} catch (Exception unreadable) {
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Schedule_ErrorRows'));
		}
		try {
			GrantPaymentService.saveSchedule(grantId, frequency, rows);
		} catch (GrantPaymentService.PaymentException e) {
			throw UserErrors.message(e.getMessage());
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.saveSchedule', grantId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
		}
	}

	/**
	 * Marks one payment Received; the received automation fills its date (R-GP3). Returns what it
	 * replaced, for Undo (modules-17).
	 */
	@AuraEnabled
	public static FundersUndoState markReceived(Id paymentId) {
		if (!Schema.SObjectType.Grant_Payment__c.isUpdateable()) {
			throw UserErrors.message(
				BarnHelp.text('Funders', 'Funders_Pipeline_ErrorNoPermission')
			);
		}
		try {
			return GrantPaymentService.markReceived(paymentId);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.markReceived', paymentId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
		}
	}

	/**
	 * modules-17: Undo for Mark Received, from what markReceived returned: the payment goes back
	 * to Expected and its Received ledger entry is removed.
	 */
	@AuraEnabled
	public static void undoReceived(Id paymentId, String status, Date receivedDate) {
		if (!Schema.SObjectType.Grant_Payment__c.isUpdateable()) {
			throw UserErrors.message(
				BarnHelp.text('Funders', 'Funders_Pipeline_ErrorNoPermission')
			);
		}
		Boolean undone;
		try {
			undone = GrantPaymentService.undoReceived(paymentId, status, receivedDate);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.undoReceived', paymentId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
		}
		if (!undone) {
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Undo_Changed'));
		}
	}
}
