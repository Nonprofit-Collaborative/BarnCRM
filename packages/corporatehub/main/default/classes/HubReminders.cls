/**
 * The Corporate Hub step of BarnCRM's nightly run (ADR-NEXT `NEXT-corporate-hub-module.md`
 * decision 7; canonical model R-AG1, R-CR1): renews or expires agreements past their end date,
 * then sends each owner one bell reminder per date for the obligations, agreements and document
 * reviews coming due. It is also the module's one way to send a bell notification (`notify`).
 *
 * It runs as whoever scheduled the nightly run, in system mode (ADR-0021): it reads every active
 * record and writes only the module's bookkeeping (Reminded For, a renewed End Date, Expired).
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

	private static Id typeId;
	private static Boolean typeLookedUp = false;

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
			if (remind) {
				obligations = obligations();
				documents = documents();
			}
			update as system agreements;
			update as system obligations;
			update as system documents;
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
		try {
			Id notificationType = notificationType();
			if (notificationType == null) {
				return;
			}
			Messaging.CustomNotification notification = new Messaging.CustomNotification();
			notification.setNotificationTypeId(notificationType);
			notification.setTitle(title.abbreviate(250));
			notification.setBody(body.abbreviate(750));
			notification.setTargetId(targetId);
			notification.send(recipientIds);
		} catch (Exception refused) {
			ErrorLogger.log(refused, CONTEXT, targetId);
		}
	}

	private static Id notificationType() {
		if (!typeLookedUp) {
			typeLookedUp = true;
			try {
				List<SObject> types = Database.queryWithBinds(
					'SELECT Id FROM CustomNotificationType WHERE DeveloperName = :name LIMIT 1', // detection-only: dynamic, and an org without it is caught below
					new Map<String, Object>{ 'name' => NOTIFICATION_TYPE },
					AccessLevel.SYSTEM_MODE
				);
				typeId = types.isEmpty() ? null : types[0].Id;
			} catch (QueryException notInThisEdition) {
				typeId = null;
			}
		}
		return typeId;
	}
}
