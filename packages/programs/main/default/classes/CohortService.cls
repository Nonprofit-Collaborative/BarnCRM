/**
 * Cohort membership and session scheduling (P-11, canonical model 29ZA5 and 29ZA6). Membership
 * is the enrollment's Cohort (R-EN8), so adding a person changes or creates an enrollment, in
 * user mode, through the enrollment rules (R-EN1 to R-EN3). Each person succeeds or fails alone
 * (R-CO3). Scheduling creates one session per date it is given (R-SE4).
 */
public with sharing class CohortService {
	/** What an add did: how many people were added, and who was refused and why. */
	public class Outcome {
		public Integer added = 0;
		public List<Refusal> refusals = new List<Refusal>();
	}

	public class Refusal {
		public String personName;
		public String message;

		Refusal(String personName, String message) {
			this.personName = personName;
			this.message = message;
		}
	}

	/**
	 * Moves these open enrollments of the cohort's program into it, and each of these people
	 * into it: through their open enrollment in the program if they have one the user can see,
	 * else through a new enrollment at stage Enrolled.
	 */
	public static Outcome addMembers(Cohort__c cohort, Set<Id> enrollmentIds, Set<Id> personIds) {
		Outcome outcome = new Outcome();
		List<Enrollment__c> toUpdate = new List<Enrollment__c>();
		List<String> updateNames = new List<String>();
		List<Enrollment__c> toInsert = new List<Enrollment__c>();
		List<String> insertNames = new List<String>();

		Map<Id, Enrollment__c> chosen = new Map<Id, Enrollment__c>(
			CohortSelector.selectEnrollments(enrollmentIds)
		);
		for (Id enrollmentId : enrollmentIds) {
			Enrollment__c enrollment = chosen.get(enrollmentId);
			if (enrollment == null) {
				outcome.refusals.add(
					new Refusal(String.valueOf(enrollmentId), Label.Programs_Cohort_NotFoundOne)
				);
			} else if (
				enrollment.Program__c != cohort.Program__c ||
				!EnrollmentService.isOpen(enrollment.Stage__c)
			) {
				outcome.refusals.add(
					new Refusal(personNameOf(enrollment), Label.Programs_Cohort_NotOpen)
				);
			} else if (enrollment.Cohort__c != cohort.Id) {
				toUpdate.add(new Enrollment__c(Id = enrollment.Id, Cohort__c = cohort.Id));
				updateNames.add(personNameOf(enrollment));
			}
		}

		if (!personIds.isEmpty()) {
			Map<Id, String> names = CohortSelector.selectPersonNames(personIds);
			Map<Id, Enrollment__c> openByPerson = new Map<Id, Enrollment__c>();
			for (Enrollment__c open : CohortSelector.selectOpenFor(cohort.Program__c, personIds)) {
				Id person = open.Contact__c != null ? open.Contact__c : open.Account__c;
				if (!openByPerson.containsKey(person)) {
					openByPerson.put(person, open);
				}
			}
			for (Id personId : personIds) {
				String name = names.containsKey(personId)
					? names.get(personId)
					: String.valueOf(personId);
				Enrollment__c open = openByPerson.get(personId);
				if (open != null) {
					if (open.Cohort__c != cohort.Id && !chosen.containsKey(open.Id)) {
						toUpdate.add(new Enrollment__c(Id = open.Id, Cohort__c = cohort.Id));
						updateNames.add(name);
					}
					continue;
				}
				Enrollment__c enrollment = new Enrollment__c(
					Program__c = cohort.Program__c,
					Stage__c = EnrollmentService.STAGE_ENROLLED,
					Cohort__c = cohort.Id
				);
				if (personId.getSObjectType() == Contact.SObjectType) {
					enrollment.Contact__c = personId;
				} else {
					enrollment.Account__c = personId;
				}
				toInsert.add(enrollment);
				insertNames.add(name);
			}
		}

		collect(Database.update(toUpdate, false, AccessLevel.USER_MODE), updateNames, outcome);
		collect(Database.insert(toInsert, false, AccessLevel.USER_MODE), insertNames, outcome);
		return outcome;
	}

	/** Empties the enrollment's Cohort when it names this cohort; the enrollment is kept. */
	public static void removeMember(Id cohortId, Id enrollmentId) {
		Map<Id, Enrollment__c> found = new Map<Id, Enrollment__c>(
			CohortSelector.selectEnrollments(new Set<Id>{ enrollmentId })
		);
		Enrollment__c enrollment = found.get(enrollmentId);
		if (enrollment == null || enrollment.Cohort__c != cohortId) {
			throw UserErrors.message(Label.Programs_Cohort_NotFoundOne);
		}
		Database.update(
			new List<Enrollment__c>{ new Enrollment__c(Id = enrollmentId, Cohort__c = null) },
			true,
			AccessLevel.USER_MODE
		);
	}

	/** The name of the person an enrollment names, as far as the user can see it. */
	public static String personNameOf(Enrollment__c enrollment) {
		if (enrollment.Contact__c != null) {
			return enrollment.Contact__r == null ? null : enrollment.Contact__r.Name;
		}
		if (enrollment.Account__c != null) {
			return enrollment.Account__r == null ? null : enrollment.Account__r.Name;
		}
		return null;
	}

	private static void collect(
		List<Database.SaveResult> results,
		List<String> names,
		Outcome outcome
	) {
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				outcome.added++;
			} else {
				outcome.refusals.add(new Refusal(names[i], results[i].getErrors()[0].getMessage()));
			}
		}
	}
}
