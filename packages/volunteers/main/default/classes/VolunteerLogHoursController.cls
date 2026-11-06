/**
 * What the Log Hours action calls (modules-14): the person picker's object and filter, and the
 * values the form starts with on the record it opens from. A person prefills the person, a job
 * prefills the job, and a shift prefills the job, the shift, the date and the shift's length.
 * The save itself is the standard record form, so every hours rule and the approval status apply
 * as on New.
 */
public with sharing class VolunteerLogHoursController {
	private static final String PERSON_ACCOUNT_FILTER_FIELD = 'IsPersonAccount'; // detection-only: a record picker filter field, sent only after isPersonAccountOrg found person accounts

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
				Volunteer_Shift__c shift = shifts[0];
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
		return context;
	}
}
