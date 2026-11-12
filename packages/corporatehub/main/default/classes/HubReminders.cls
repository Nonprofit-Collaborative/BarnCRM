/**
 * The Corporate Hub step of BarnCRM's nightly run (ADR-NEXT `NEXT-corporate-hub-module.md`
 * decision 7; canonical model R-AG1, R-CR1): renews or expires agreements past their end date,
 * then sends each owner one bell reminder per date for the obligations, agreements, document
 * reviews, board terms and the GDPR records (CH-05: DPIA reviews, data subject requests, unreported
 * breaches) coming due, and links each erasure to its request (R-DS2). It is also the module's one
 * way to send a bell notification (`notify`).
 *
 * It runs as whoever scheduled the nightly run, in system mode (ADR-0021): it reads every active
 * record and writes only the module's bookkeeping (Reminded For, a renewed End Date, Expired, the
 * Erasure Record link).
 */
public with sharing class HubReminders implements Schedulable {
	/** The step's key on the Nightly Jobs page. */
	public static final String JOB_NAME = 'BarnCRM Corporate Hub Reminders';
	private static final String NOTIFICATION_TYPE = 'Corporate_Hub_Reminder';
	private static final String CONTEXT = 'HubReminders';
	private static final String ACTIVE = 'Active';
	private static final Integer MAX_ROWS = 2000;

	/** The most reminders one night sends; the rest go the next night. */
	@TestVisible
	private static Integer maxReminders = 200;

	/** Every notification handed to the platform this transaction, by title, for the tests. */
	@TestVisible
	private static List<String> sentTitles = new List<String>();

	private Integer sent = 0;
	private Date today;
	private Integer settingDays;

	/** The step as BarnCRM's nightly run lists it, with a switch that ships on. */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				BarnHelp.text('CorporateHub', 'CorporateHub_Nightly_StepName'),
				6,
				45,
				new HubReminders()
			)
			.withSwitch(true);
	}

	public void execute(SchedulableContext jobContext) {
		try {
			today = Date.today();
			settingDays = CorporateHubSettings.reminderDays();
			Boolean remind = CorporateHubSettings.remindersEnabled();
			List<Agreement__c> agreements = agreements(remind);
			List<Compliance_Obligation__c> obligations = new List<Compliance_Obligation__c>();
			List<Hub_Document__c> documents = new List<Hub_Document__c>();
			List<Board_Member__c> seats = new List<Board_Member__c>();
			List<SObject> privacy = new List<SObject>();
			if (remind) {
				obligations = obligations();
				documents = documents();
				seats = seats();
				privacy.addAll(dpiaReviews());
				privacy.addAll(breaches());
			}
			update as system agreements;
			update as system obligations;
			update as system documents;
			update as system seats;
			update as system privacy;
			update as system requests(remind);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT);
		}
	}

	/** R-AG1, then R-CR1 for agreements: the rows changed, renewed, expired or reminded. */
	private List<Agreement__c> agreements(Boolean remind) {
		List<Agreement__c> changed = new List<Agreement__c>();
		for (Agreement__c row : [
			SELECT
				Id,
				Name,
				OwnerId,
				End_Date__c,
				Auto_Renews__c,
				Renewal_Months__c,
				Notice_Days__c,
				Reminder_Days__c,
				Reminded_For__c,
				Status__c
			FROM Agreement__c
			WHERE Status__c = :ACTIVE AND End_Date__c != NULL
			WITH SYSTEM_MODE
			ORDER BY End_Date__c
			LIMIT :MAX_ROWS
		]) {
			Boolean renewed = renew(row);
			if (row.Status__c != ACTIVE) {
				changed.add(row);
				continue;
			}
			Integer notice = row.Notice_Days__c == null ? 0 : row.Notice_Days__c.intValue();
			Date target = row.End_Date__c.addDays(-notice);
			Boolean reminded =
				remind &&
				due(target, row.Reminder_Days__c, row.Reminded_For__c) &&
				send(
					row.OwnerId,
					BarnHelp.text(
						'CorporateHub',
						'CorporateHub_Reminder_AgreementTitle',
						new List<Object>{ row.Name, target.format() }
					),
					row.Id
				);
			if (reminded) {
				row.Reminded_For__c = target;
			}
			if (renewed || reminded) {
				changed.add(row);
			}
		}
		return changed;
	}

	/** An agreement past its end date renews by its term, or expires. True when it changed. */
	@TestVisible
	private Boolean renew(Agreement__c row) {
		if (row.End_Date__c >= today) {
			return false;
		}
		Integer months = row.Renewal_Months__c == null ? 0 : row.Renewal_Months__c.intValue();
		if (row.Auto_Renews__c != true || months < 1) {
			row.Status__c = 'Expired';
			return true;
		}
		while (row.End_Date__c < today) {
			row.End_Date__c = row.End_Date__c.addMonths(months);
		}
		return true;
	}

	private List<Compliance_Obligation__c> obligations() {
		List<Compliance_Obligation__c> changed = new List<Compliance_Obligation__c>();
		for (Compliance_Obligation__c row : [
			SELECT Id, Name, OwnerId, Due_Date__c, Reminder_Days__c, Reminded_For__c
			FROM Compliance_Obligation__c
			WHERE Status__c = :ACTIVE AND Due_Date__c != NULL
			WITH SYSTEM_MODE
			ORDER BY Due_Date__c
			LIMIT :MAX_ROWS
		]) {
			if (
				due(row.Due_Date__c, row.Reminder_Days__c, row.Reminded_For__c) &&
				send(
					row.OwnerId,
					BarnHelp.text(
						'CorporateHub',
						'CorporateHub_Reminder_ObligationTitle',
						new List<Object>{ row.Name, row.Due_Date__c.format() }
					),
					row.Id
				)
			) {
				row.Reminded_For__c = row.Due_Date__c;
				changed.add(row);
			}
		}
		return changed;
	}

	private List<Hub_Document__c> documents() {
		List<Hub_Document__c> changed = new List<Hub_Document__c>();
		for (Hub_Document__c row : [
			SELECT Id, Name, OwnerId, Review_Date__c, Reminded_For__c
			FROM Hub_Document__c
			WHERE Status__c = :ACTIVE AND Review_Date__c != NULL
			WITH SYSTEM_MODE
			ORDER BY Review_Date__c
			LIMIT :MAX_ROWS
		]) {
			if (
				due(row.Review_Date__c, null, row.Reminded_For__c) &&
				send(
					row.OwnerId,
					BarnHelp.text(
						'CorporateHub',
						'CorporateHub_Reminder_ReviewTitle',
						new List<Object>{ row.Name, row.Review_Date__c.format() }
					),
					row.Id
				)
			) {
				row.Reminded_For__c = row.Review_Date__c;
				changed.add(row);
			}
		}
		return changed;
	}

	/** R-BM2: the board's owner hears of each current seat whose term ends soon. */
	private List<Board_Member__c> seats() {
		List<Board_Member__c> changed = new List<Board_Member__c>();
		for (Board_Member__c row : [
			SELECT Id, Person__r.Name, Board__r.Name, Board__r.OwnerId, Term_End__c, Reminded_For__c
			FROM Board_Member__c
			WHERE Is_Current__c = TRUE AND Term_End__c != NULL AND Board__r.Status__c = :ACTIVE
			WITH SYSTEM_MODE
			ORDER BY Term_End__c
			LIMIT :MAX_ROWS
		]) {
			if (
				due(row.Term_End__c, null, row.Reminded_For__c) &&
				send(
					row.Board__r.OwnerId,
					BarnHelp.text(
						'CorporateHub',
						'CorporateHub_Reminder_TermTitle',
						new List<Object>{
							row.Person__r?.Name,
							row.Board__r.Name,
							row.Term_End__c.format()
						}
					),
					row.Id
				)
			) {
				row.Reminded_For__c = row.Term_End__c;
				changed.add(row);
			}
		}
		return changed;
	}

	/** R-PA1: the owner of an Active processing activity that needs a DPIA, before its review. */
	private List<SObject> dpiaReviews() {
		return remindEach(
			[
				SELECT Id, Name, OwnerId, DPIA_Review_Date__c, Reminded_For__c
				FROM Processing_Activity__c
				WHERE
					Status__c = :ACTIVE
					AND DPIA_Required__c = TRUE
					AND DPIA_Review_Date__c != NULL
				WITH SYSTEM_MODE
				ORDER BY DPIA_Review_Date__c
				LIMIT :MAX_ROWS
			],
			'DPIA_Review_Date__c',
			BarnHelp.text('CorporateHub', 'CorporateHub_Reminder_DpiaTitle')
		);
	}

	/** R-DB1: the owner of a breach not yet reported, and not assessed as unlikely to be a risk. */
	private List<SObject> breaches() {
		return remindEach(
			[
				SELECT Id, Name, OwnerId, Authority_Deadline__c, Reminded_For__c
				FROM Data_Breach__c
				WHERE
					Status__c != 'Closed'
					AND Risk__c != 'Unlikely'
					AND Authority_Notified_At__c = NULL
				WITH SYSTEM_MODE
				ORDER BY Discovered_At__c
				LIMIT :MAX_ROWS
			],
			'Authority_Deadline__c',
			BarnHelp.text('CorporateHub', 'CorporateHub_Reminder_BreachTitle')
		);
	}

	/**
	 * R-DS2, then R-DS1: an open erasure request whose number Erase Person was given as the
	 * reference gets its Erasure Record, whether or not reminders are on; then the owner of each
	 * open request is reminded before its due date.
	 */
	private List<Data_Subject_Request__c> requests(Boolean remind) {
		List<Data_Subject_Request__c> open = [
			SELECT
				Id,
				Name,
				OwnerId,
				Due_Date__c,
				Reminded_For__c,
				Request_Type__c,
				Erasure_Record__c
			FROM Data_Subject_Request__c
			WHERE Status__c IN ('Received', 'In Progress')
			WITH SYSTEM_MODE
			ORDER BY Due_Date__c
			LIMIT :MAX_ROWS
		];
		Set<String> names = new Set<String>();
		for (Data_Subject_Request__c row : open) {
			if (row.Request_Type__c == 'Erasure' && row.Erasure_Record__c == null) {
				names.add(row.Name);
			}
		}
		Map<String, Id> erasures = new Map<String, Id>();
		if (!names.isEmpty()) {
			for (Erasure__c erasure : [
				SELECT Id, Request_Reference__c
				FROM Erasure__c
				WHERE Request_Reference__c IN :names
				WITH SYSTEM_MODE
				ORDER BY CreatedDate
			]) {
				erasures.put(erasure.Request_Reference__c.trim().toLowerCase(), erasure.Id);
			}
		}
		Map<Id, Data_Subject_Request__c> changed = new Map<Id, Data_Subject_Request__c>();
		for (Data_Subject_Request__c row : open) {
			Id erasure = names.contains(row.Name) ? erasures.get(row.Name.toLowerCase()) : null;
			if (erasure != null) {
				row.Erasure_Record__c = erasure;
				changed.put(row.Id, row);
			}
			if (
				remind &&
				remindRow(
					row,
					row.Due_Date__c,
					BarnHelp.text('CorporateHub', 'CorporateHub_Reminder_RequestTitle')
				)
			) {
				changed.put(row.Id, row);
			}
		}
		return changed.values();
	}

	/** One reminder per date for each row, the date read from `dateField` (a date or a date and time). */
	private List<SObject> remindEach(List<SObject> rows, String dateField, String title) {
		List<SObject> changed = new List<SObject>();
		for (SObject row : rows) {
			Object value = row.get(dateField);
			Date target = value instanceof Datetime ? ((Datetime) value).date() : (Date) value;
			if (remindRow(row, target, title)) {
				changed.add(row);
			}
		}
		return changed;
	}

	/** Reminds the row's owner about `target` once; `title` takes the row's name and the date. */
	private Boolean remindRow(SObject row, Date target, String title) {
		if (
			due(target, null, (Date) row.get('Reminded_For__c')) &&
			send(
				(Id) row.get('OwnerId'),
				String.format(title, new List<Object>{ row.get('Name'), target.format() }),
				row.Id
			)
		) {
			row.put('Reminded_For__c', target);
			return true;
		}
		return false;
	}

	/** Within the record's reminder days (or the setting's), overdue included, not yet reminded. */
	private Boolean due(Date target, Decimal recordDays, Date remindedFor) {
		Integer lead = recordDays == null ? settingDays : Math.max(0, recordDays.intValue());
		return target != null && target <= today.addDays(lead) && remindedFor != target;
	}

	/** One reminder to a record's owner, within tonight's cap. A queue owner is skipped. */
	private Boolean send(Id ownerId, String title, Id recordId) {
		if (
			sent >= maxReminders ||
			ownerId == null ||
			ownerId.getSObjectType() != User.SObjectType
		) {
			return false;
		}
		sent++;
		notify(
			new Set<String>{ ownerId },
			title,
			BarnHelp.text('CorporateHub', 'CorporateHub_Reminder_Body'),
			recordId
		);
		return true;
	}

	/**
	 * Sends one bell notification of the module's own type. Never throws: an org whose edition
	 * has no custom notifications sends nothing, and a refused send is written to the Error Log.
	 */
	public static void notify(Set<String> recipientIds, String title, String body, Id targetId) {
		if (recipientIds == null || recipientIds.isEmpty()) {
			return;
		}
		sentTitles.add(title);
		JobNotifier.ownType(NOTIFICATION_TYPE, recipientIds, title, body, targetId, CONTEXT);
	}
}
