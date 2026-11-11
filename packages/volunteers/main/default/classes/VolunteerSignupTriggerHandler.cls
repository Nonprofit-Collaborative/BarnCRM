/**
 * Record-level rules for Volunteer_Signup__c, run by the Core trigger dispatcher through the
 * registry row `Volunteer_Signup_Rules`, switchable from the console (ADR-0017). The rules are
 * `VolunteerSignupService` methods; this class decides which sign-ups each applies to.
 */
@NamespaceAccessible
public with sharing class VolunteerSignupTriggerHandler extends TriggerHandler {
	@NamespaceAccessible
	public VolunteerSignupTriggerHandler() {
		return;
	}

	public override String getName() {
		return 'VolunteerSignupTriggerHandler';
	}

	public override void beforeInsert() {
		List<Volunteer_Signup__c> signups = (List<Volunteer_Signup__c>) newRecords();
		VolunteerSignupService.refuseSecondSignups(signups);
		VolunteerCapacity.waitlistWhatDoesNotFit(signups, null);
		VolunteerMinors.flag(signups, null);
	}

	public override void beforeUpdate() {
		Map<Id, Volunteer_Signup__c> previousById = (Map<Id, Volunteer_Signup__c>) oldRecordsById();
		List<Volunteer_Signup__c> moved = new List<Volunteer_Signup__c>();
		for (Volunteer_Signup__c signup : (List<Volunteer_Signup__c>) newRecords()) {
			Volunteer_Signup__c previous = previousById.get(signup.Id);
			if (
				signup.Volunteer_Shift__c != previous.Volunteer_Shift__c ||
				signup.Contact__c != previous.Contact__c ||
				signup.Account__c != previous.Account__c
			) {
				moved.add(signup);
			}
		}
		if (!moved.isEmpty()) {
			VolunteerSignupService.refuseSecondSignups(moved);
		}
		VolunteerCapacity.waitlistWhatDoesNotFit(
			(List<Volunteer_Signup__c>) newRecords(),
			previousById
		);
		VolunteerMinors.flag((List<Volunteer_Signup__c>) newRecords(), previousById);
	}

	public override void afterInsert() {
		List<Volunteer_Signup__c> signups = (List<Volunteer_Signup__c>) newRecords();
		VolunteerSignupService.createHoursForAttendance(signups, null);
		VolunteerMinors.requestConsent(signups, null);
		VolunteerStanding.extendFor(signups, null);
	}

	/** R-VU8: places a deleted booking held go to the people waiting. */
	public override void afterDelete() {
		VolunteerCapacity.promote(
			VolunteerCapacity.heldShifts((List<Volunteer_Signup__c>) oldRecords())
		);
	}

	/**
	 * R-VU2 on undelete: restoring a sign-up for a person who has since been booked onto the
	 * same shift again is refused. Undeleting writes no attendance hours.
	 */
	public override void afterUndelete() {
		VolunteerSignupService.refuseSecondSignups((List<Volunteer_Signup__c>) newRecords());
	}

	public override void afterUpdate() {
		List<Volunteer_Signup__c> signups = (List<Volunteer_Signup__c>) newRecords();
		Map<Id, Volunteer_Signup__c> previousById = (Map<Id, Volunteer_Signup__c>) oldRecordsById();
		VolunteerSignupService.createHoursForAttendance(signups, previousById);
		VolunteerCapacity.promote(VolunteerCapacity.freedShifts(signups, previousById));
		VolunteerMinors.requestConsent(signups, previousById);
		VolunteerStanding.extendFor(signups, previousById);
	}
}
