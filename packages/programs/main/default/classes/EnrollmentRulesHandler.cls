/**
 * R-EN1's person half (`ProgramPersonRule`, QA-F4: never an organization or household account)
 * and R-EN2 for Enrollment__c, run by the Core trigger dispatcher through the registry row
 * `Enrollment_Rules`, which always runs: it enforces a rule rather than doing work for anyone, so
 * no switch, pause or bypass reaches it (ADR-0024). A second open enrollment for the same person
 * in the same program is refused on insert, on undelete, and on an update that changes the
 * program, the person or the stage of an enrollment that is open after the save. It also keeps
 * program capacity (P-09, R-EN10) through `EnrollmentCapacity`, which does nothing while
 * Waitlist When Full is off.
 */
@NamespaceAccessible
public with sharing class EnrollmentRulesHandler extends TriggerHandler {
	@NamespaceAccessible
	public EnrollmentRulesHandler() {
		return;
	}

	public override String getName() {
		return 'EnrollmentRulesHandler';
	}

	public override void beforeInsert() {
		ProgramPersonRule.refuseNonPersonAccounts(newRecords(), null);
		EnrollmentCapacity.waitlistWhatDoesNotFit((List<Enrollment__c>) newRecords(), null);
		EnrollmentService.refuseSecondOpenEnrollments((List<Enrollment__c>) newRecords());
	}

	/** P-09 (R-EN10): places freed by an enrollment leaving Enrolled go to the waitlist. */
	public override void afterUpdate() {
		EnrollmentCapacity.promote(
			EnrollmentCapacity.freedPrograms(
				(List<Enrollment__c>) newRecords(),
				(Map<Id, Enrollment__c>) oldRecordsById()
			)
		);
	}

	public override void afterDelete() {
		EnrollmentCapacity.promote(
			EnrollmentCapacity.freedPrograms((List<Enrollment__c>) oldRecords(), null)
		);
	}

	public override void beforeUpdate() {
		ProgramPersonRule.refuseNonPersonAccounts(newRecords(), oldRecordsById());
		Map<Id, Enrollment__c> previousById = (Map<Id, Enrollment__c>) oldRecordsById();
		EnrollmentCapacity.waitlistWhatDoesNotFit((List<Enrollment__c>) newRecords(), previousById);
		List<Enrollment__c> changed = new List<Enrollment__c>();
		for (Enrollment__c enrollment : (List<Enrollment__c>) newRecords()) {
			Enrollment__c previous = previousById.get(enrollment.Id);
			if (
				enrollment.Program__c != previous.Program__c ||
				enrollment.Contact__c != previous.Contact__c ||
				enrollment.Account__c != previous.Account__c ||
				enrollment.Stage__c != previous.Stage__c
			) {
				changed.add(enrollment);
			}
		}
		if (!changed.isEmpty()) {
			EnrollmentService.refuseSecondOpenEnrollments(changed);
		}
	}

	/** Restoring an open enrollment for a person since enrolled again is refused. */
	public override void afterUndelete() {
		EnrollmentService.refuseSecondOpenEnrollments((List<Enrollment__c>) newRecords());
	}
}
