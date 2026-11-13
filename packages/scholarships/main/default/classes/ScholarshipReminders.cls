/**
 * The Scholarships step of BarnCRM's nightly run (ADR-0204
 * `0204-scholarships-outbound-grants-module.md` decision 11): moves cycles on by their dates
 * (R-SG2), fills the signed form links still blank on Draft applications and open requirements,
 * and sends the program owner one bell reminder per due date for each open requirement coming
 * due, with an optional email to the recipient (R-SG13).
 *
 * It runs as whoever scheduled the nightly run, in system mode (ADR-0021): it reads every open
 * record and writes only the module's bookkeeping (Status of a cycle, a form link, Reminded For).
 */
public with sharing class ScholarshipReminders implements Schedulable {
	public static final String JOB_NAME = 'BarnCRM Scholarships Reminders';
	private static final Integer MAX_ROWS = 2000;

	/** The most reminders one night sends; the rest go the next night. */
	@TestVisible
	private static Integer maxReminders = 200;

	/**
	 * The step as BarnCRM's nightly run lists it, with a switch that ships on. It can be started
	 * now from the Nightly Jobs panel: a second run the same day reminds no one twice.
	 */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				BarnHelp.text('Scholarships', 'Scholarships_Nightly_StepName'),
				6,
				50,
				new ScholarshipReminders()
			)
			.withSwitch(true)
			.runnableNow();
	}

	public void execute(SchedulableContext jobContext) {
		try {
			Date today = Date.today();
			List<Award_Cycle__c> cycles = new List<Award_Cycle__c>();
			for (Award_Cycle__c cycle : [
				SELECT Id, Status__c, Open_Date__c, Close_Date__c
				FROM Award_Cycle__c
				WHERE
					(Status__c = 'Planned'
					AND Open_Date__c <= :today)
					OR (Status__c = 'Open'
					AND Close_Date__c < :today)
				WITH SYSTEM_MODE
				LIMIT :MAX_ROWS
			]) {
				Boolean closed = cycle.Close_Date__c != null && cycle.Close_Date__c < today;
				cycle.Status__c = closed ? 'Reviewing' : 'Open';
				cycles.add(cycle);
			}
			update as system cycles;
			List<Award_Application__c> drafts = [
				SELECT Id
				FROM Award_Application__c
				WHERE
					Status__c = 'Draft'
					AND Form_Link__c = NULL
					AND Cycle__r.Application_Form_Key__c != NULL
				WITH SYSTEM_MODE
				LIMIT 200
			];
			for (Award_Application__c draft : drafts) {
				draft.Form_Link__c = ScholarshipFormAttachment.linkFor(draft.Id);
			}
			update as system drafts;
			update as system requirements(today);
		} catch (Exception e) {
			ErrorLogger.log(e, 'ScholarshipReminders');
		}
	}

	/** Open requirements: a blank report link filled, and R-SG13 reminders. The rows changed. */
	private List<Award_Requirement__c> requirements(Date today) {
		Boolean remind = ScholarshipsSettings.remindersEnabled();
		Boolean email = remind && ScholarshipsSettings.emailRecipients();
		Date horizon = today.addDays(ScholarshipsSettings.reminderDays());
		List<Award_Requirement__c> changed = new List<Award_Requirement__c>();
		List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
		Integer sent = 0;
		for (Award_Requirement__c row : [
			SELECT
				Id,
				Name,
				Due_Date__c,
				Reminded_For__c,
				Form_Link__c,
				Award__r.Name,
				Award__r.Contact__c,
				Award__r.Contact__r.Email,
				Award__r.Cycle__r.Report_Form_Key__c,
				Award__r.Cycle__r.Program__r.OwnerId
			FROM Award_Requirement__c
			WHERE Status__c = 'Open' AND Award__r.Status__c IN ('Accepted', 'Active')
			WITH SYSTEM_MODE
			ORDER BY Due_Date__c NULLS LAST
			LIMIT :MAX_ROWS
		]) {
			Boolean touched = false;
			if (row.Form_Link__c == null && row.Award__r.Cycle__r.Report_Form_Key__c != null) {
				row.Form_Link__c = ScholarshipFormAttachment.linkFor(row.Id);
				touched = row.Form_Link__c != null;
			}
			if (
				remind &&
				sent < maxReminders &&
				row.Due_Date__c != null &&
				row.Due_Date__c <= horizon &&
				row.Reminded_For__c != row.Due_Date__c
			) {
				String title = BarnHelp.text(
					'Scholarships',
					'Scholarships_Reminder_Title',
					new List<Object>{ row.Name, row.Award__r.Name, row.Due_Date__c.format() }
				);
				Scholarships.notify(
					new Set<String>{ row.Award__r.Cycle__r.Program__r.OwnerId },
					title,
					row.Id
				);
				if (email && row.Award__r.Contact__r?.Email != null) {
					emails.add(message(row, title));
				}
				row.Reminded_For__c = row.Due_Date__c;
				touched = true;
				sent++;
			}
			if (touched) {
				changed.add(row);
			}
		}
		send(emails);
		return changed;
	}

	private static Messaging.SingleEmailMessage message(Award_Requirement__c row, String title) {
		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		mail.setTargetObjectId(row.Award__r.Contact__c);
		mail.setSaveAsActivity(false);
		mail.setSubject(title);
		mail.setPlainTextBody(
			BarnHelp.text(
				'Scholarships',
				'Scholarships_Reminder_Email',
				new List<Object>{ row.Name, row.Due_Date__c.format(), row.Form_Link__c ?? '' }
			)
		);
		return mail;
	}

	/** Sends within the org's email limit; a refusal is logged, never thrown. */
	private static void send(List<Messaging.SingleEmailMessage> emails) {
		if (emails.isEmpty()) {
			return;
		}
		try {
			Messaging.reserveSingleEmailCapacity(emails.size());
			Messaging.sendEmail(emails, false);
		} catch (Exception refused) {
			ErrorLogger.log(refused, 'ScholarshipReminders.send');
		}
	}
}
