/**
 * Awards (SG-04), disbursements (SG-05), conditions (SG-09) and renewals (SG-06): decisions
 * (R-SG9), the award letter (R-SG1), schedules (R-SG12), Mark Paid (R-SG11 is enforced by
 * `AwardPaymentRulesHandler`), requirements, Start Renewal (R-SG10) and the accounting export.
 * Records only: BarnCRM moves no money. User mode throughout (ADR-0204
 * `0204-scholarships-outbound-grants-module.md`, decisions 8 to 11).
 */
public with sharing class ScholarshipAwards {
	public static final String PAID = 'Paid';
	public static final String SCHEDULED = 'Scheduled';
	public static final Set<String> OPEN_REQUIREMENT = new Set<String>{ 'Open', 'Submitted' };
	private static final Integer MAX_ROWS = 2000;

	/** One disbursement on the award panel or in the export. */
	public class Payment {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String award;
		@AuraEnabled
		public String recipient;
		@AuraEnabled
		public String payee;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Date scheduled;
		@AuraEnabled
		public Date paid;
		@AuraEnabled
		public String method;
		@AuraEnabled
		public String reference;
		@AuraEnabled
		public String program;
		@AuraEnabled
		public String cycle;
		@AuraEnabled
		public Boolean held = false;
	}

	/** R-SG9: Award (with an amount) or Decline an application. Returns the award, or null. */
	public static Id decide(Id applicationId, Boolean award, Decimal amount) {
		Scholarships.requireManage();
		Award_Application__c application = [
			SELECT Id, Cycle__c, Contact__c, Organization__c, Amount_Requested__c
			FROM Award_Application__c
			WHERE Id = :applicationId
			WITH USER_MODE
		];
		if (award != true) {
			update as user new Award_Application__c(Id = applicationId, Status__c = 'Declined');
			return null;
		}
		Decimal given = amount ?? application.Amount_Requested__c;
		if (given == null || given <= 0) {
			throw Scholarships.refuse(
				BarnHelp.text('Scholarships', 'Scholarships_Decide_AmountNeeded')
			);
		}
		Award__c row = new Award__c(
			Cycle__c = application.Cycle__c,
			Application__c = applicationId,
			Contact__c = application.Contact__c,
			Organization__c = application.Organization__c,
			Amount__c = given,
			Status__c = 'Offered',
			Decision_Date__c = Date.today()
		);
		insert as user row;
		update as user new Award_Application__c(Id = applicationId, Status__c = 'Awarded');
		return row.Id;
	}

	/** R-SG1: the award letter as a PDF filed on the award. Returns the file's ContentDocument. */
	public static Id makeLetter(Id awardId) {
		Award__c row = award(awardId);
		String template = row.Cycle__r.Program__r.Letter_Template__c;
		if (String.isBlank(template)) {
			template = BarnHelp.text('Scholarships', 'Scholarships_Letter_Default');
		}
		Map<String, String> values = new Map<String, String>{
			'{Recipient}' => row.Organization__r?.Name ?? row.Contact__r?.Name ?? '',
			'{Program}' => row.Cycle__r.Program__r.Name,
			'{Cycle}' => row.Cycle__r.Name,
			'{Amount}' => row.Amount__c.format(),
			'{Conditions}' => row.Conditions__c ?? '',
			'{Organization}' => UserInfo.getOrganizationName() ?? '',
			'{Date}' => Date.today().format()
		};
		String html = template.escapeHtml4();
		for (String tag : values.keySet()) {
			html = html.replace(tag, values.get(tag).escapeHtml4());
		}
		html =
			'<html><body style="font-family: sans-serif;">' +
			html.replace('\n', '<br/>') +
			'</body></html>';
		ContentVersion file = new ContentVersion(
			Title = BarnHelp.text(
				'Scholarships',
				'Scholarships_Letter_Title',
				new List<Object>{ row.Name }
			),
			PathOnClient = row.Name + '.pdf',
			VersionData = Blob.toPdf(html),
			FirstPublishLocationId = awardId
		);
		insert as user file;
		update as user new Award__c(Id = awardId, Letter_Sent_Date__c = Date.today());
		return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :file.Id WITH USER_MODE]
		.ContentDocumentId;
	}

	/** Records the recipient's answer to an Offered award. */
	public static void respond(Id awardId, Boolean accepted) {
		Award__c row = award(awardId);
		if (row.Status__c != 'Offered') {
			throw Scholarships.refuse(
				BarnHelp.text('Scholarships', 'Scholarships_Award_NotOffered')
			);
		}
		update as user new Award__c(
			Id = awardId,
			Status__c = accepted == true ? 'Accepted' : 'Declined',
			Accepted_Date__c = accepted == true ? Date.today() : null
		);
	}

	/** R-SG12: equal payments of the amount not yet scheduled, a number of months apart. */
	public static Integer buildSchedule(
		Id awardId,
		Integer count,
		Date firstDate,
		Integer monthsApart
	) {
		Award__c row = award(awardId);
		Decimal left = row.Amount__c - (row.Scheduled_Amount__c ?? 0);
		if (count == null || count < 1 || count > 60 || left <= 0 || firstDate == null) {
			throw Scholarships.refuse(
				BarnHelp.text('Scholarships', 'Scholarships_Schedule_Invalid')
			);
		}
		Decimal each = (left / count).setScale(2, RoundingMode.DOWN);
		String payee = row.Organization__r?.Name ?? row.Contact__r?.Name;
		List<Award_Payment__c> payments = new List<Award_Payment__c>();
		for (Integer i = 0; i < count; i++) {
			payments.add(
				new Award_Payment__c(
					Award__c = awardId,
					Amount__c = i == count - 1 ? left - each * (count - 1) : each,
					Scheduled_Date__c = firstDate.addMonths(i * Math.max(0, monthsApart ?? 1)),
					Status__c = SCHEDULED,
					Payee_Name__c = payee
				)
			);
		}
		insert as user payments;
		if (row.Status__c == 'Accepted') {
			update as user new Award__c(Id = awardId, Status__c = 'Active');
		}
		return payments.size();
	}

	/** Mark Paid; the trigger handler refuses it without Manage Scholarships or with a condition open. */
	public static void markPaid(Id paymentId, Date paidOn, String method, String reference) {
		update as user new Award_Payment__c(
			Id = paymentId,
			Status__c = PAID,
			Paid_Date__c = paidOn ?? Date.today(),
			Payment_Method__c = String.isBlank(method) ? null : method,
			Reference__c = reference
		);
	}

	/** Met (anyone who can edit) or Waived (Manage Scholarships). */
	public static void setRequirement(Id requirementId, String status) {
		if (status != 'Met' && status != 'Waived') {
			throw Scholarships.refuse(BarnHelp.text('Scholarships', 'Scholarships_Error_Generic'));
		}
		if (status == 'Waived') {
			Scholarships.requireManage();
		}
		update as user new Award_Requirement__c(Id = requirementId, Status__c = status);
	}

	/** R-SG10: a Draft application in the program's next Planned or Open cycle. */
	public static Id startRenewal(Id awardId) {
		Award__c row = award(awardId);
		if (!row.Renewable__c) {
			throw Scholarships.refuse(
				BarnHelp.text('Scholarships', 'Scholarships_Renewal_NotRenewable')
			);
		}
		List<Award_Cycle__c> next = [
			SELECT Id
			FROM Award_Cycle__c
			WHERE
				Program__c = :row.Cycle__r.Program__c
				AND Id != :row.Cycle__c
				AND Status__c IN ('Planned', 'Open')
			WITH USER_MODE
			ORDER BY Open_Date__c NULLS LAST
			LIMIT 1
		];
		if (next.isEmpty()) {
			throw Scholarships.refuse(
				BarnHelp.text('Scholarships', 'Scholarships_Renewal_NoCycle')
			);
		}
		Award_Application__c renewal = new Award_Application__c(
			Cycle__c = next[0].Id,
			Contact__c = row.Contact__c,
			Organization__c = row.Organization__c,
			Renewal_Of__c = awardId,
			Status__c = 'Draft'
		);
		insert as user renewal;
		return renewal.Id;
	}

	/** An award's disbursements, each marked when an open condition holds it back. */
	public static List<Payment> payments(Id awardId) {
		List<Award_Payment__c> rows = [
			SELECT
				Id,
				Name,
				Award__c,
				Payee_Name__c,
				Amount__c,
				Status__c,
				Scheduled_Date__c,
				Paid_Date__c,
				Payment_Method__c,
				Reference__c
			FROM Award_Payment__c
			WHERE Award__c = :awardId
			WITH USER_MODE
			ORDER BY Scheduled_Date__c NULLS LAST, Name
		];
		return toPayments(rows, held(new Set<Id>{ awardId }));
	}

	/**
	 * The export (SG-05): disbursements scheduled or paid in the range, not cancelled, as rows for
	 * the CSV the browser builds; their Exported Date is stamped today.
	 */
	public static List<Payment> export(Date fromDate, Date toDate) {
		Scholarships.requireManage();
		if (fromDate == null || toDate == null || fromDate > toDate) {
			throw Scholarships.refuse(BarnHelp.text('Scholarships', 'Scholarships_Export_Range'));
		}
		List<Award_Payment__c> rows = [
			SELECT
				Id,
				Name,
				Award__c,
				Award__r.Name,
				Award__r.Contact__r.Name,
				Award__r.Organization__r.Name,
				Award__r.Cycle__r.Name,
				Award__r.Cycle__r.Program__r.Name,
				Payee_Name__c,
				Amount__c,
				Status__c,
				Scheduled_Date__c,
				Paid_Date__c,
				Payment_Method__c,
				Reference__c
			FROM Award_Payment__c
			WHERE
				Status__c != 'Cancelled'
				AND ((Paid_Date__c >= :fromDate
				AND Paid_Date__c <= :toDate)
				OR (Status__c = :SCHEDULED
				AND Scheduled_Date__c >= :fromDate
				AND Scheduled_Date__c <= :toDate))
			WITH USER_MODE
			ORDER BY Scheduled_Date__c, Name
			LIMIT :MAX_ROWS
		];
		Set<Id> awardIds = new Set<Id>();
		List<Award_Payment__c> stamped = new List<Award_Payment__c>();
		for (Award_Payment__c row : rows) {
			awardIds.add(row.Award__c);
			stamped.add(new Award_Payment__c(Id = row.Id, Exported_Date__c = Date.today()));
		}
		List<Payment> out = toPayments(rows, held(awardIds));
		update as user stamped;
		return out;
	}

	/** Scheduled disbursements due in the next days, for the Scholarships and Grants page. */
	public static List<Payment> due(Integer days) {
		List<Award_Payment__c> rows = [
			SELECT
				Id,
				Name,
				Award__c,
				Award__r.Name,
				Award__r.Contact__r.Name,
				Award__r.Organization__r.Name,
				Award__r.Cycle__r.Name,
				Award__r.Cycle__r.Program__r.Name,
				Payee_Name__c,
				Amount__c,
				Status__c,
				Scheduled_Date__c,
				Paid_Date__c,
				Payment_Method__c,
				Reference__c
			FROM Award_Payment__c
			WHERE Status__c = :SCHEDULED AND Scheduled_Date__c <= :Date.today().addDays(days)
			WITH USER_MODE
			ORDER BY Scheduled_Date__c
			LIMIT 200
		];
		Set<Id> awardIds = new Set<Id>();
		for (Award_Payment__c row : rows) {
			awardIds.add(row.Award__c);
		}
		return toPayments(rows, held(awardIds));
	}

	/**
	 * R-SG11: for each award, the disbursements its open conditions hold back; the award's own Id
	 * in the set means a condition naming no disbursement holds back all of them.
	 */
	public static Map<Id, Set<Id>> held(Set<Id> awardIds) {
		Map<Id, Set<Id>> byAward = new Map<Id, Set<Id>>();
		for (Award_Requirement__c condition : [
			SELECT Award__c, Disbursement__c
			FROM Award_Requirement__c
			WHERE Award__c IN :awardIds AND Type__c = 'Condition' AND Status__c IN :OPEN_REQUIREMENT
			WITH SYSTEM_MODE
		]) {
			if (!byAward.containsKey(condition.Award__c)) {
				byAward.put(condition.Award__c, new Set<Id>());
			}
			byAward.get(condition.Award__c).add(condition.Disbursement__c ?? condition.Award__c);
		}
		return byAward;
	}

	/** Whether a disbursement of an award is held back. */
	public static Boolean isHeld(Map<Id, Set<Id>> held, Id awardId, Id paymentId) {
		Set<Id> holding = held.get(awardId);
		return holding != null && (holding.contains(awardId) || holding.contains(paymentId));
	}

	private static List<Payment> toPayments(List<Award_Payment__c> rows, Map<Id, Set<Id>> held) {
		List<Payment> out = new List<Payment>();
		for (Award_Payment__c row : rows) {
			Payment one = new Payment();
			one.id = row.Id;
			one.name = row.Name;
			one.award = row.Award__r?.Name;
			one.recipient = row.Award__r?.Organization__r?.Name ?? row.Award__r?.Contact__r?.Name;
			one.payee = row.Payee_Name__c;
			one.amount = row.Amount__c;
			one.status = row.Status__c;
			one.scheduled = row.Scheduled_Date__c;
			one.paid = row.Paid_Date__c;
			one.method = row.Payment_Method__c;
			one.reference = row.Reference__c;
			one.program = row.Award__r?.Cycle__r?.Program__r?.Name;
			one.cycle = row.Award__r?.Cycle__r?.Name;
			one.held = row.Status__c == SCHEDULED && isHeld(held, row.Award__c, row.Id);
			out.add(one);
		}
		return out;
	}

	private static Award__c award(Id awardId) {
		return [
			SELECT
				Id,
				Name,
				Amount__c,
				Status__c,
				Conditions__c,
				Renewable__c,
				Scheduled_Amount__c,
				Contact__c,
				Contact__r.Name,
				Organization__c,
				Organization__r.Name,
				Cycle__c,
				Cycle__r.Name,
				Cycle__r.Program__c,
				Cycle__r.Program__r.Name,
				Cycle__r.Program__r.Letter_Template__c
			FROM Award__c
			WHERE Id = :awardId
			WITH USER_MODE
		];
	}
}
