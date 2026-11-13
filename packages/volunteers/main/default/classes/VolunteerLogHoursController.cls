/**
 * What the Log Hours action calls (modules-14): the person picker's object and filter, and the
 * values the form starts with on the record it opens from. A person prefills the person and,
 * when they are signed up for a shift today, that shift (D-200 R12); a job prefills the job; and
 * a shift prefills the job, the shift, the date and the shift's length. The save itself is the
 * standard record form, so every hours rule and the approval status apply as on New.
 */
public with sharing class VolunteerLogHoursController {
	private static final String PERSON_ACCOUNT_FILTER_FIELD = 'IsPersonAccount'; // detection-only: a record picker filter field, sent only after isPersonAccountOrg found person accounts
	/** Sign-ups that still mean the person came or is coming. */
	private static final Set<String> LIVE_SIGNUPS = new Set<String>{
		'Signed up',
		'Confirmed',
		'Attended'
	};

	/** The form's starting values. */
	public class Context {
		@AuraEnabled
		public Boolean canCreate = false;
		@AuraEnabled
		public Boolean hasPersonAccounts = false;
		@AuraEnabled
		public String personObject = 'Contact';
		@AuraEnabled
		public String personFilterField;
		@AuraEnabled
		public Id personId;
		@AuraEnabled
		public Id jobId;
		@AuraEnabled
		public Id shiftId;
		@AuraEnabled
		public Date dateWorked;
		@AuraEnabled
		public Decimal hours;
	}

	@AuraEnabled
	public static Context getContext(Id recordId) {
		Context context = new Context();
		context.canCreate = Schema.SObjectType.Volunteer_Hours__c.isCreateable();
		context.hasPersonAccounts = HouseholdService.isPersonAccountOrg();
		if (context.hasPersonAccounts) {
			context.personObject = 'Account';
			context.personFilterField = PERSON_ACCOUNT_FILTER_FIELD;
		}
		if (recordId == null) {
			return context;
		}
		Schema.SObjectType recordType = recordId.getSObjectType();
		if (recordType == Contact.SObjectType) {
			context.personObject = 'Contact';
			context.personFilterField = null;
			context.personId = recordId;
		} else if (recordType == Account.SObjectType) {
			if (!VolunteerLetterSelector.personAccounts(new Set<Id>{ recordId }).isEmpty()) {
				context.personId = recordId;
			}
		} else if (recordType == Volunteer_Job__c.SObjectType) {
			context.jobId = recordId;
		} else if (recordType == Volunteer_Shift__c.SObjectType) {
			List<Volunteer_Shift__c> shifts = [
				SELECT Id, Volunteer_Job__c, Start_Time__c, End_Time__c
				FROM Volunteer_Shift__c
				WHERE Id = :recordId
				WITH USER_MODE
				LIMIT 1
			];
			if (!shifts.isEmpty()) {
				applyShift(context, shifts[0]);
			}
		}
		if (context.personId != null) {
			applyShift(context, todaysShift(context.personId));
		}
		return context;
	}

	/**
	 * The shift the person is signed up for today, so logging their hours after it starts with
	 * the job and the shift chosen: the latest one already started, else the first one still to
	 * come; null when they have none today.
	 */
	private static Volunteer_Shift__c todaysShift(Id personId) {
		Datetime now = ShiftScheduleService.now();
		Date today = ShiftScheduleService.orgDate(now);
		Datetime fromTime = now.addDays(-1);
		Datetime toTime = now.addDays(1);
		Volunteer_Shift__c chosen;
		for (Volunteer_Signup__c signup : [
			SELECT
				Volunteer_Shift__r.Id,
				Volunteer_Shift__r.Volunteer_Job__c,
				Volunteer_Shift__r.Start_Time__c,
				Volunteer_Shift__r.End_Time__c
			FROM Volunteer_Signup__c
			WHERE
				(Contact__c = :personId
				OR Account__c = :personId)
				AND Status__c IN :LIVE_SIGNUPS
				AND Volunteer_Shift__r.Start_Time__c >= :fromTime
				AND Volunteer_Shift__r.Start_Time__c <= :toTime
			WITH USER_MODE
			ORDER BY Volunteer_Shift__r.Start_Time__c ASC
			LIMIT 20
		]) {
			Volunteer_Shift__c shift = signup.Volunteer_Shift__r;
			if (ShiftScheduleService.orgDate(shift.Start_Time__c) != today) {
				continue;
			}
			if (chosen == null || shift.Start_Time__c <= now) {
				chosen = shift;
			}
		}
		return chosen;
	}

	/** A shift fills the job, the shift, the day it starts and its length. */
	private static void applyShift(Context context, Volunteer_Shift__c shift) {
		if (shift == null) {
			return;
		}
		context.shiftId = shift.Id;
		context.jobId = shift.Volunteer_Job__c;
		if (shift.Start_Time__c != null) {
			context.dateWorked = ShiftScheduleService.orgDate(shift.Start_Time__c);
		}
		if (
			shift.Start_Time__c != null &&
			shift.End_Time__c != null &&
			shift.End_Time__c > shift.Start_Time__c
		) {
			Decimal millis = shift.End_Time__c.getTime() - shift.Start_Time__c.getTime();
			context.hours = (millis / 3600000).setScale(2);
		}
	}
}
