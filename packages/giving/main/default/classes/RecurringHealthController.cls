/**
 * The Recurring Donor Health page (G-27, canonical model Section 25V, rules R-RH3 and R-RH4):
 * active recurring gifts by frequency for monthly recurring revenue, the Save the Sustainer list,
 * twelve months of gifts received on recurring gifts, and the count of unmatched processor
 * events. Everything runs as the person, so each figure is what they may see (commitments are
 * private, 2026-10-29 security review G-L5). The page turns amounts into monthly values
 * (`recurringHealthModel`), so this class returns plain rows.
 */
public with sharing class RecurringHealthController {
	private static final String CONTEXT = 'Recurring donor health page';
	private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
	private static final String KEY_EXPIRY_DAYS = 'Recurring_Card_Expiry_Days__c';
	private static final Integer DEFAULT_EXPIRY_DAYS = 60;
	private static final Integer MAX_ROWS = 200;

	public class HealthPage {
		@AuraEnabled
		public List<Slice> byFrequency = new List<Slice>();
		@AuraEnabled
		public List<Row> rows = new List<Row>();
		@AuraEnabled
		public List<Month> months = new List<Month>();
		@AuraEnabled
		public Integer unmatched;
		@AuraEnabled
		public Integer expiryDays;
	}

	/** Active recurring gifts of one frequency: their total amount each time, and how many. */
	public class Slice {
		@AuraEnabled
		public String frequency;
		@AuraEnabled
		public Decimal total;
		@AuraEnabled
		public Integer count;
	}

	/** One gift on the Save the Sustainer list, with what put it there. */
	public class Row {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Id donorId;
		@AuraEnabled
		public String donorName;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public String frequency;
		@AuraEnabled
		public Integer failedCharges;
		@AuraEnabled
		public Date lastFailedCharge;
		@AuraEnabled
		public Date cardExpires;
		@AuraEnabled
		public Date cancelledAtProcessor;
		@AuraEnabled
		public Date overdueSince;
	}

	/** Gifts received on recurring gifts in one calendar month. */
	public class Month {
		@AuraEnabled
		public Integer year;
		@AuraEnabled
		public Integer month;
		@AuraEnabled
		public Decimal total;
	}

	@AuraEnabled
	public static HealthPage getPage() {
		try {
			HealthPage page = new HealthPage();
			page.expiryDays = expiryDays();
			for (AggregateResult slice : [
				SELECT Frequency__c frequency, SUM(Amount__c) total, COUNT(Id) howMany
				FROM Commitment__c
				WHERE Type__c = 'Recurring' AND Status__c = 'Active'
				WITH USER_MODE
				GROUP BY Frequency__c
			]) {
				Slice row = new Slice();
				row.frequency = (String) slice.get('frequency');
				row.total = (Decimal) slice.get('total');
				row.count = (Integer) slice.get('howMany');
				page.byFrequency.add(row);
			}
			page.rows = atRisk(Date.today().addDays(page.expiryDays));
			page.months = months();
			if (Schema.SObjectType.Recurring_Gift_Event__c.isAccessible()) {
				page.unmatched = [
					SELECT COUNT()
					FROM Recurring_Gift_Event__c
					WHERE Match_Status__c = :RecurringGiftUpkeep.UNMATCHED
					WITH USER_MODE
				];
			}
			return page;
		} catch (Exception caught) {
			throw UserErrors.wrap(
				caught,
				false,
				CONTEXT,
				BarnHelp.text('Giving', 'Giving_RecurringHealth_Unexpected')
			);
		}
	}

	/** A follow-up task for the person, about the gift and its donor. Returns the task. */
	@AuraEnabled
	public static Id createFollowUp(Id commitmentId) {
		try {
			Commitment__c gift = [
				SELECT Id, Donor_Contact__c, Donor_Contact__r.Name, Donor_Account__r.Name
				FROM Commitment__c
				WHERE Id = :commitmentId
				WITH USER_MODE
			];
			String donor = gift.Donor_Contact__c != null
				? gift.Donor_Contact__r.Name
				: gift.Donor_Account__r?.Name;
			Task followUp = new Task(
				Subject = BarnHelp.text(
						'Giving',
						'Giving_RecurringHealth_TaskSubject',
						new List<Object>{ donor }
					)
					.abbreviate(255),
				ActivityDate = Date.today(),
				Status = AskReminderService.TASK_STATUS,
				Priority = AskReminderService.TASK_PRIORITY,
				OwnerId = UserInfo.getUserId(),
				WhatId = gift.Id,
				WhoId = gift.Donor_Contact__c
			);
			insert as user followUp;
			return followUp.Id;
		} catch (Exception caught) {
			throw UserErrors.wrapShowingDml(
				caught,
				BarnHelp.text('Giving', 'Giving_RecurringHealth_Unexpected')
			);
		}
	}

	/** R-RH3: active recurring gifts with a failed charge, a card expiring, a cancellation or an overdue payment. */
	private static List<Row> atRisk(Date expiryCutoff) {
		Map<Id, Commitment__c> found = new Map<Id, Commitment__c>(
			[
				SELECT Id
				FROM Commitment__c
				WHERE
					Type__c = 'Recurring'
					AND Status__c = 'Active'
					AND (Failed_Charges__c > 0
					OR Card_Expires__c <= :expiryCutoff
					OR Processor_Cancelled__c != NULL)
				WITH USER_MODE
				LIMIT :MAX_ROWS
			]
		);
		for (Installment__c late : [
			SELECT Commitment__c
			FROM Installment__c
			WHERE
				Status__c = 'Overdue'
				AND Commitment__r.Type__c = 'Recurring'
				AND Commitment__r.Status__c = 'Active'
			WITH USER_MODE
			ORDER BY Due_Date__c
			LIMIT :MAX_ROWS
		]) {
			found.put(late.Commitment__c, null);
		}
		List<Row> rows = new List<Row>();
		for (Commitment__c gift : [
			SELECT
				Id,
				Name,
				Amount__c,
				Frequency__c,
				Donor_Contact__c,
				Donor_Contact__r.Name,
				Donor_Account__c,
				Donor_Account__r.Name,
				Failed_Charges__c,
				Last_Failed_Charge__c,
				Card_Expires__c,
				Processor_Cancelled__c,
				(
					SELECT Due_Date__c
					FROM Installments__r
					WHERE Status__c = 'Overdue'
					ORDER BY Due_Date__c
					LIMIT 1
				)
			FROM Commitment__c
			WHERE Id IN :found.keySet()
			WITH USER_MODE
			ORDER BY Amount__c DESC
			LIMIT :MAX_ROWS
		]) {
			Row row = new Row();
			row.id = gift.Id;
			row.name = gift.Name;
			row.donorId = gift.Donor_Contact__c != null
				? gift.Donor_Contact__c
				: gift.Donor_Account__c;
			row.donorName = gift.Donor_Contact__c != null
				? gift.Donor_Contact__r.Name
				: gift.Donor_Account__r?.Name;
			row.amount = gift.Amount__c;
			row.frequency = gift.Frequency__c;
			row.failedCharges = gift.Failed_Charges__c == null
				? 0
				: gift.Failed_Charges__c.intValue();
			row.lastFailedCharge = gift.Last_Failed_Charge__c;
			row.cardExpires = gift.Card_Expires__c != null &&
				gift.Card_Expires__c <= expiryCutoff
				? gift.Card_Expires__c
				: null;
			row.cancelledAtProcessor = gift.Processor_Cancelled__c;
			row.overdueSince = gift.Installments__r.isEmpty()
				? null
				: gift.Installments__r[0].Due_Date__c;
			rows.add(row);
		}
		return rows;
	}

	/** R-RH4: received gifts on recurring gifts, by calendar month, this month and the eleven before. */
	private static List<Month> months() {
		Date since = Date.today().toStartOfMonth().addMonths(-11);
		List<Month> months = new List<Month>();
		for (AggregateResult total : [
			SELECT
				CALENDAR_YEAR(Gift_Date__c) y,
				CALENDAR_MONTH(Gift_Date__c) m,
				SUM(Amount__c) total
			FROM Gift__c
			WHERE
				Commitment__r.Type__c = 'Recurring'
				AND Status__c = 'Received'
				AND Gift_Date__c >= :since
			WITH USER_MODE
			GROUP BY CALENDAR_YEAR(Gift_Date__c), CALENDAR_MONTH(Gift_Date__c)
		]) {
			Month row = new Month();
			row.year = (Integer) total.get('y');
			row.month = (Integer) total.get('m');
			row.total = (Decimal) total.get('total');
			months.add(row);
		}
		return months;
	}

	/** The Recurring Card Expiry Days setting, 0 to 365; 60 when unset or unreadable. */
	@TestVisible
	private static Integer expiryDays() {
		Object value = SettingsService.getValue(SETTINGS_OBJECT, KEY_EXPIRY_DAYS);
		Integer days;
		try {
			days = value == null ? null : Decimal.valueOf(String.valueOf(value).trim()).intValue();
		} catch (TypeException unreadable) {
			days = null;
		}
		return days == null || days < 0 || days > 365 ? DEFAULT_EXPIRY_DAYS : days;
	}
}
