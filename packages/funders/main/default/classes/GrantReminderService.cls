/**
 * Grant requirement reminders (F-02, R-GQ3, R-GQ4): one task and one email to the person who owes
 * the work, once per due date.
 *
 * The person is the requirement's Assigned To when that user is active, otherwise the grant's
 * owner when that is an active user; nobody active means no reminder (Health Check still lists an
 * overdue requirement). The task is on the grant, due on the due date. A requirement is stamped
 * with its due date only once its task saved (or when tasks are off), so a failed task is tried
 * again the next morning; the email goes only to stamped requirements, so it is never repeated,
 * and a failed email is logged. Emails are addressed by user record (`setTargetObjectId`).
 */
public with sharing class GrantReminderService {
	private static final String LOG_CONTEXT = 'GrantReminderService';
	/** How far past its due date an unreminded requirement is still reminded. */
	public static final Integer OVERDUE_DAYS = 30;
	public static final String TASK_STATUS = 'Not Started';
	public static final String TASK_PRIORITY = 'Normal';

	/** One `Messaging.sendEmail` call for the chunk, partial success on; a test sends nothing. */
	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();

	/** Whether a run should start: the module is on and at least one reminder setting is on. */
	public static Boolean isActive() {
		return !ModuleManagerService.turnedOff()
				.contains(FundersAccessSync.MODULE_NAME.toLowerCase()) &&
			(FundersSettings.reminderTasksEnabled() || FundersSettings.reminderEmailsEnabled());
	}

	/** The oldest due date the run reminds. */
	public static Date oldestDue(Date today) {
		return today.addDays(-OVERDUE_DAYS);
	}

	/** The latest due date the run reminds. */
	public static Date windowEnd(Date today, Integer leadDays) {
		return today.addDays(leadDays);
	}

	/**
	 * Whether a requirement is due a reminder today: open, due within the window, and not yet
	 * reminded for this due date.
	 */
	public static Boolean isDue(Grant_Requirement__c requirement, Date today, Integer leadDays) {
		return GrantRequirementService.isOpen(requirement.Status__c) &&
			requirement.Due_Date__c != null &&
			requirement.Due_Date__c >= oldestDue(today) &&
			requirement.Due_Date__c <= windowEnd(today, leadDays) &&
			requirement.Reminder_Sent_For__c != requirement.Due_Date__c;
	}

	/** The person to remind: the active assignee, else the grant's active owner, else null. */
	public static Id recipientFor(Grant_Requirement__c requirement, Set<Id> activeUsers) {
		if (
			requirement.Assigned_To__c != null && activeUsers.contains(requirement.Assigned_To__c)
		) {
			return requirement.Assigned_To__c;
		}
		Id owner = requirement.Grant__r == null ? null : requirement.Grant__r.OwnerId;
		return owner != null && activeUsers.contains(owner) ? owner : null;
	}

	/**
	 * Reminds this chunk of requirements: tasks first, then the stamp, then the emails. Returns
	 * how many were reminded (stamped).
	 */
	public static Integer remind(List<Grant_Requirement__c> requirements, Date today) {
		if (requirements == null || requirements.isEmpty() || !isActive()) {
			return 0;
		}
		Integer leadDays = FundersSettings.reminderLeadDays();
		Boolean tasksOn = FundersSettings.reminderTasksEnabled();
		Boolean emailsOn = FundersSettings.reminderEmailsEnabled();

		Set<Id> candidates = new Set<Id>();
		for (Grant_Requirement__c requirement : requirements) {
			candidates.add(requirement.Assigned_To__c);
			if (requirement.Grant__r != null) {
				candidates.add(requirement.Grant__r.OwnerId);
			}
		}
		candidates.remove(null);
		Set<Id> active = GrantReminderSelector.activeUsers(candidates);

		List<Grant_Requirement__c> due = new List<Grant_Requirement__c>();
		List<Id> recipients = new List<Id>();
		for (Grant_Requirement__c requirement : requirements) {
			Id recipient = recipientFor(requirement, active);
			if (recipient != null && isDue(requirement, today, leadDays)) {
				due.add(requirement);
				recipients.add(recipient);
			}
		}
		if (due.isEmpty()) {
			return 0;
		}

		List<Grant_Requirement__c> ready = new List<Grant_Requirement__c>();
		List<Id> readyRecipients = new List<Id>();
		if (tasksOn) {
			List<Task> tasks = new List<Task>();
			for (Integer i = 0; i < due.size(); i++) {
				tasks.add(taskFor(due[i], recipients[i]));
			}
			List<Database.SaveResult> saved = Database.insert(
				tasks,
				false,
				AccessLevel.SYSTEM_MODE
			);
			String failure;
			for (Integer i = 0; i < due.size(); i++) {
				if (saved[i].isSuccess()) {
					ready.add(due[i]);
					readyRecipients.add(recipients[i]);
				} else if (failure == null && !saved[i].getErrors().isEmpty()) {
					failure = saved[i].getErrors()[0].getMessage();
				}
			}
			logShortfall(
				Label.Funders_Reminder_TaskFailed,
				due.size() - ready.size(),
				due,
				failure
			);
		} else {
			ready.addAll(due);
			readyRecipients.addAll(recipients);
		}

		List<Grant_Requirement__c> stamps = new List<Grant_Requirement__c>();
		for (Grant_Requirement__c requirement : ready) {
			stamps.add(
				new Grant_Requirement__c(
					Id = requirement.Id,
					Reminder_Sent_For__c = requirement.Due_Date__c
				)
			);
		}
		List<Database.SaveResult> stamped = Database.update(stamps, false, AccessLevel.SYSTEM_MODE);
		List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
		Integer reminded = 0;
		String stampFailure;
		for (Integer i = 0; i < ready.size(); i++) {
			if (!stamped[i].isSuccess()) {
				if (stampFailure == null && !stamped[i].getErrors().isEmpty()) {
					stampFailure = stamped[i].getErrors()[0].getMessage();
				}
				continue;
			}
			reminded++;
			if (emailsOn) {
				messages.add(messageFor(ready[i], readyRecipients[i]));
			}
		}
		logShortfall(
			Label.Funders_Reminder_StampFailed,
			ready.size() - reminded,
			ready,
			stampFailure
		);
		sendAll(messages, due);
		return reminded;
	}

	private static void sendAll(List<Messaging.SingleEmailMessage> messages, List<Object> due) {
		if (messages.isEmpty()) {
			return;
		}
		Integer failed = 0;
		String failure;
		try {
			for (EmailSendOutcome outcome : emailSender.send(messages)) {
				if (!outcome.sent) {
					failed++;
					failure = failure == null ? outcome.error : failure;
				}
			}
		} catch (Exception refused) {
			failed = messages.size();
			failure = refused.getMessage();
		}
		logShortfall(Label.Funders_Reminder_SendFailed, failed, due, failure);
	}

	private static void logShortfall(
		String template,
		Integer count,
		List<Object> outOf,
		String why
	) {
		if (count <= 0) {
			return;
		}
		ErrorLogger.logMessage(
			String.format(
				template,
				new List<Object>{ count, outOf.size(), why == null ? '' : why }
			),
			LOG_CONTEXT,
			ErrorLogger.SEVERITY_WARNING
		);
	}

	/** The reminder task: for the person, on the grant, due on the due date. */
	@TestVisible
	private static Task taskFor(Grant_Requirement__c requirement, Id recipient) {
		return new Task(
			Subject = String.format(
				Label.Funders_Reminder_TaskSubject,
				new List<Object>{ requirement.Name, grantName(requirement) }
			),
			Description = describe(requirement),
			ActivityDate = requirement.Due_Date__c,
			Status = TASK_STATUS,
			Priority = TASK_PRIORITY,
			OwnerId = recipient,
			WhatId = requirement.Grant__c
		);
	}

	/** The reminder email, addressed by user record so no outside address is used. */
	@TestVisible
	private static Messaging.SingleEmailMessage messageFor(
		Grant_Requirement__c requirement,
		Id recipient
	) {
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setTargetObjectId(recipient);
		message.setSaveAsActivity(false);
		message.setSubject(
			String.format(
				Label.Funders_Reminder_EmailSubject,
				new List<Object>{ requirement.Name, grantName(requirement) }
			)
		);
		message.setPlainTextBody(
			describe(requirement) +
				'\n\n' +
				URL.getOrgDomainUrl().toExternalForm() +
				'/' +
				requirement.Grant__c
		);
		return message;
	}

	private static String grantName(Grant_Requirement__c requirement) {
		return requirement.Grant__r == null ? '' : requirement.Grant__r.Name;
	}

	private static String describe(Grant_Requirement__c requirement) {
		String funder = requirement.Grant__r == null ||
			requirement.Grant__r.Funder__r == null
			? ''
			: requirement.Grant__r.Funder__r.Name;
		return String.format(
			Label.Funders_Reminder_Body,
			new List<Object>{
				requirement.Name,
				grantName(requirement),
				funder,
				requirement.Due_Date__c.format()
			}
		);
	}
}
