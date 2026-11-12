/**
 * Program capacity and the waitlist (P-09, canonical model R-EN10; ADR-0198 volunteer
 * self-service and waitlists, decision 5). With Waitlist When Full on and Capacity set, an
 * enrollment saved as Enrolled into a full program is saved as Waitlisted, and Waitlisted
 * enrollments move to Enrolled, oldest first, when places free. Core's `WaitlistQueue` decides who
 * fits; each enrollment takes one place.
 *
 * The enrollment half is called from `EnrollmentRulesHandler`, which always runs. This class is
 * also the handler of the registry row `Program_Capacity`, which promotes when a program's
 * Capacity is raised or cleared. Places are counted in system mode over every enrollment, so one
 * the user cannot see (R-EN7) still counts and still moves up.
 */
@NamespaceAccessible
public inherited sharing class EnrollmentCapacity extends TriggerHandler {
	private static final String PROGRAM = 'Program__c';
	private static final String LOG_CONTEXT = 'EnrollmentCapacity.promote';

	@NamespaceAccessible
	public EnrollmentCapacity() {
		return;
	}

	public override String getName() {
		return 'EnrollmentCapacity';
	}

	/** A program whose Capacity is raised or cleared promotes its waitlist. */
	public override void afterUpdate() {
		Map<Id, SObject> previousById = oldRecordsById();
		Set<Id> raised = new Set<Id>();
		for (Program__c program : (List<Program__c>) newRecords()) {
			Decimal before = ((Program__c) previousById.get(program.Id)).Capacity__c;
			if (before != null && (program.Capacity__c == null || program.Capacity__c > before)) {
				raised.add(program.Id);
			}
		}
		promote(raised);
	}

	/** Programs' Waitlist When Full, off unless saved on. */
	public static Boolean waitlistEnabled() {
		try {
			return SettingsService.getValue('Programs_Settings__c', 'Waitlist_Enabled__c') == true;
		} catch (Exception unreadable) {
			// Never saved or unreadable: the shipped value, off, applies.
			return false;
		}
	}

	/**
	 * Before save: of the enrollments that become Enrolled in a program (new, moved to Enrolled or
	 * moved to another program), those that do not fit are saved as Waitlisted, in the order given.
	 */
	public static void waitlistWhatDoesNotFit(
		List<Enrollment__c> enrollments,
		Map<Id, Enrollment__c> previousById
	) {
		if (!waitlistEnabled()) {
			return;
		}
		List<Enrollment__c> candidates = new List<Enrollment__c>();
		Set<Id> programIds = new Set<Id>();
		Set<Id> ownIds = new Set<Id>();
		for (Enrollment__c enrollment : enrollments) {
			Enrollment__c previous = previousById == null ? null : previousById.get(enrollment.Id);
			if (
				enrollment.Stage__c == EnrollmentService.STAGE_ENROLLED &&
				enrollment.Program__c != null &&
				(previous == null ||
				previous.Stage__c != EnrollmentService.STAGE_ENROLLED ||
				previous.Program__c != enrollment.Program__c)
			) {
				candidates.add(enrollment);
				programIds.add(enrollment.Program__c);
				if (enrollment.Id != null) {
					ownIds.add(enrollment.Id);
				}
			}
		}
		if (candidates.isEmpty()) {
			return;
		}
		// The fits come back in the candidates' order, so one pass matches them by identity: two new
		// enrollments can be equal field for field.
		List<SObject> fits = WaitlistQueue.fitting(
			freePlaces(programIds, ownIds),
			candidates,
			PROGRAM,
			null
		);
		Integer next = 0;
		for (Enrollment__c candidate : candidates) {
			if (next < fits.size() && fits[next] === candidate) {
				next++;
			} else {
				candidate.Stage__c = EnrollmentService.STAGE_WAITLISTED;
			}
		}
	}

	/** After update or delete: the programs an Enrolled enrollment left. */
	public static Set<Id> freedPrograms(
		List<Enrollment__c> enrollments,
		Map<Id, Enrollment__c> previousById
	) {
		Set<Id> freed = new Set<Id>();
		for (Enrollment__c enrollment : enrollments) {
			Enrollment__c previous = previousById == null
				? enrollment
				: previousById.get(enrollment.Id);
			Boolean deleted = previousById == null;
			if (
				previous.Stage__c == EnrollmentService.STAGE_ENROLLED &&
				(deleted ||
				enrollment.Stage__c != EnrollmentService.STAGE_ENROLLED ||
				enrollment.Program__c != previous.Program__c)
			) {
				freed.add(previous.Program__c);
			}
		}
		return freed;
	}

	/**
	 * Moves Waitlisted enrollments in these programs to Enrolled, oldest first, while places are
	 * free; R-EN3 fills their Start Date. One that cannot be saved is logged and the others saved.
	 */
	public static void promote(Set<Id> programIds) {
		programIds.remove(null);
		if (programIds.isEmpty() || !waitlistEnabled()) {
			return;
		}
		Map<Id, Decimal> free = freePlaces(programIds, new Set<Id>());
		// A program whose Capacity was cleared has no entry in free, so everyone waiting fits.
		List<Enrollment__c> waiting = [
			SELECT Id, Program__c
			FROM Enrollment__c
			WHERE Program__c IN :programIds AND Stage__c = :EnrollmentService.STAGE_WAITLISTED
			WITH SYSTEM_MODE
			ORDER BY CreatedDate, Id
			LIMIT 2000
		];
		List<Enrollment__c> promoted = new List<Enrollment__c>();
		for (SObject fit : WaitlistQueue.fitting(free, waiting, PROGRAM, null)) {
			promoted.add(
				new Enrollment__c(Id = fit.Id, Stage__c = EnrollmentService.STAGE_ENROLLED)
			);
		}
		if (promoted.isEmpty()) {
			return;
		}
		for (
			Database.SaveResult result : Database.update(promoted, false, AccessLevel.SYSTEM_MODE)
		) {
			if (!result.isSuccess()) {
				ErrorLogger.logMessage(result.getErrors()[0].getMessage(), LOG_CONTEXT, 'Warning');
			}
		}
	}

	/**
	 * Places free in each of these programs that has a Capacity, leaving out the enrollments
	 * being saved. A program with no Capacity has no entry, so nothing in it is limited.
	 */
	private static Map<Id, Decimal> freePlaces(Set<Id> programIds, Set<Id> leaveOut) {
		Map<Id, Decimal> free = new Map<Id, Decimal>();
		for (Program__c program : [
			SELECT Id, Capacity__c
			FROM Program__c
			WHERE Id IN :programIds AND Capacity__c != NULL
			WITH SYSTEM_MODE
		]) {
			free.put(program.Id, program.Capacity__c);
		}
		if (free.isEmpty()) {
			return free;
		}
		Set<Id> limited = free.keySet();
		for (AggregateResult row : [
			SELECT Program__c programId, COUNT(Id) taken
			FROM Enrollment__c
			WHERE
				Program__c IN :limited
				AND Stage__c = :EnrollmentService.STAGE_ENROLLED
				AND Id NOT IN :leaveOut
			WITH SYSTEM_MODE
			GROUP BY Program__c
		]) {
			Id programId = (Id) row.get('programId');
			free.put(programId, free.get(programId) - (Integer) row.get('taken'));
		}
		return free;
	}
}
