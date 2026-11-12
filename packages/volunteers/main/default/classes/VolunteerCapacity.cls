/**
 * The shift waitlist (V-14, canonical model R-VU8; ADR-0198 volunteer self-service and
 * waitlists, decision 5). With Waitlist When Full on, a booking that does not fit its shift is
 * saved as Waitlisted, and Waitlisted bookings move up to Signed up, oldest first, when places
 * free. Core's `WaitlistQueue` decides who fits; a group takes its Group Size (V-16).
 *
 * Places are counted from the sign-ups, not Slots Filled, which a roll-up brings up to date a
 * moment later, and in system mode, so a booking the user cannot see, or made from the portal
 * or a public form, counts the same. Only shifts still to come are limited: history entered for
 * a past shift is never waitlisted.
 */
public inherited sharing class VolunteerCapacity {
	public static final String STATUS_SIGNED_UP = 'Signed up';
	public static final String STATUS_WAITLISTED = 'Waitlisted';
	private static final Set<String> BOOKING = new Set<String>{ STATUS_SIGNED_UP, 'Confirmed' };
	private static final Set<String> NOT_HOLDING = new Set<String>{
		VolunteerSignupService.STATUS_CANCELLED,
		STATUS_WAITLISTED
	};
	private static final String SHIFT = 'Volunteer_Shift__c';
	private static final String SIZE = 'Group_Size__c';
	private static final String LOG_CONTEXT = 'VolunteerCapacity.promote';

	/** Whether a booking holds places on its shift: anything not Cancelled or Waitlisted. */
	public static Boolean holds(Volunteer_Signup__c signup) {
		return signup != null && !NOT_HOLDING.contains(signup.Status__c);
	}

	/**
	 * Before save: of the bookings given that take more places than before (new, moved to a
	 * booking status, moved to another shift or made a bigger group), those that do not fit
	 * their shift become Waitlisted, in the order given.
	 */
	public static void waitlistWhatDoesNotFit(
		List<Volunteer_Signup__c> signups,
		Map<Id, Volunteer_Signup__c> previousById
	) {
		if (!VolunteerSettings.waitlistEnabled()) {
			return;
		}
		List<Volunteer_Signup__c> candidates = new List<Volunteer_Signup__c>();
		Set<Id> shiftIds = new Set<Id>();
		Set<Id> ownIds = new Set<Id>();
		for (Volunteer_Signup__c signup : signups) {
			Volunteer_Signup__c previous = previousById == null
				? null
				: previousById.get(signup.Id);
			if (
				BOOKING.contains(signup.Status__c) &&
				signup.Volunteer_Shift__c != null &&
				takesMore(signup, previous)
			) {
				candidates.add(signup);
				shiftIds.add(signup.Volunteer_Shift__c);
				if (signup.Id != null) {
					ownIds.add(signup.Id);
				}
			}
		}
		if (candidates.isEmpty()) {
			return;
		}
		List<SObject> fits = WaitlistQueue.fitting(
			freePlaces(shiftIds, ownIds),
			candidates,
			SHIFT,
			SIZE
		);
		for (Volunteer_Signup__c candidate : candidates) {
			if (!containsSame(fits, candidate)) {
				candidate.Status__c = STATUS_WAITLISTED;
			}
		}
	}

	/** After update: the shifts places were freed on (a booking cancelled, moved or made smaller). */
	public static Set<Id> freedShifts(
		List<Volunteer_Signup__c> signups,
		Map<Id, Volunteer_Signup__c> previousById
	) {
		Set<Id> freed = new Set<Id>();
		for (Volunteer_Signup__c signup : signups) {
			Volunteer_Signup__c previous = previousById == null
				? null
				: previousById.get(signup.Id);
			if (previous == null || !holds(previous)) {
				continue;
			}
			if (
				!holds(signup) ||
				signup.Volunteer_Shift__c != previous.Volunteer_Shift__c ||
				WaitlistQueue.placesOf(signup, SIZE) < WaitlistQueue.placesOf(previous, SIZE)
			) {
				freed.add(previous.Volunteer_Shift__c);
			}
		}
		return freed;
	}

	/** After delete: the shifts whose deleted bookings held places. */
	public static Set<Id> heldShifts(List<Volunteer_Signup__c> deleted) {
		Set<Id> shiftIds = new Set<Id>();
		for (Volunteer_Signup__c signup : deleted) {
			if (holds(signup) && signup.Volunteer_Shift__c != null) {
				shiftIds.add(signup.Volunteer_Shift__c);
			}
		}
		return shiftIds;
	}

	/**
	 * Moves Waitlisted bookings on these shifts up to Signed up, oldest first, while they fit. A
	 * booking that cannot be saved is logged and the others are saved.
	 */
	public static void promote(Set<Id> shiftIds) {
		shiftIds.remove(null);
		if (shiftIds.isEmpty() || !VolunteerSettings.waitlistEnabled()) {
			return;
		}
		Map<Id, Decimal> free = freePlaces(shiftIds, new Set<Id>());
		Set<Id> open = free.keySet();
		List<Volunteer_Signup__c> waiting = [
			SELECT Id, Volunteer_Shift__c, Group_Size__c
			FROM Volunteer_Signup__c
			WHERE Volunteer_Shift__c IN :open AND Status__c = :STATUS_WAITLISTED
			WITH SYSTEM_MODE
			ORDER BY CreatedDate, Id
			LIMIT 2000
		];
		List<Volunteer_Signup__c> promoted = new List<Volunteer_Signup__c>();
		for (SObject fit : WaitlistQueue.fitting(free, waiting, SHIFT, SIZE)) {
			promoted.add(new Volunteer_Signup__c(Id = fit.Id, Status__c = STATUS_SIGNED_UP));
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
	 * Places free on each of these shifts that is Open and still to come, leaving out the
	 * bookings being saved; a shift with no Volunteers Needed has no limit. Shifts that are past,
	 * closed or gone have no entry, so nothing on them is limited or promoted.
	 */
	private static Map<Id, Decimal> freePlaces(Set<Id> shiftIds, Set<Id> leaveOut) {
		Map<Id, Decimal> free = new Map<Id, Decimal>();
		Datetime now = Datetime.now();
		for (Volunteer_Shift__c shift : [
			SELECT Id, Volunteers_Needed__c
			FROM Volunteer_Shift__c
			WHERE Id IN :shiftIds AND Status__c = 'Open' AND Start_Time__c > :now
			WITH SYSTEM_MODE
		]) {
			// No limit is a number nothing reaches, so the shift still counts as open.
			free.put(
				shift.Id,
				shift.Volunteers_Needed__c == null ? 1000000 : shift.Volunteers_Needed__c
			);
		}
		if (free.isEmpty()) {
			return free;
		}
		Set<Id> limited = free.keySet();
		for (Volunteer_Signup__c held : [
			SELECT Volunteer_Shift__c, Group_Size__c
			FROM Volunteer_Signup__c
			WHERE
				Volunteer_Shift__c IN :limited
				AND Status__c NOT IN :NOT_HOLDING
				AND Id NOT IN :leaveOut
			WITH SYSTEM_MODE
			LIMIT 10000
		]) {
			free.put(
				held.Volunteer_Shift__c,
				free.get(held.Volunteer_Shift__c) - WaitlistQueue.placesOf(held, SIZE)
			);
		}
		return free;
	}

	private static Boolean takesMore(Volunteer_Signup__c signup, Volunteer_Signup__c previous) {
		return previous == null ||
			!holds(previous) ||
			signup.Volunteer_Shift__c != previous.Volunteer_Shift__c ||
			WaitlistQueue.placesOf(signup, SIZE) > WaitlistQueue.placesOf(previous, SIZE);
	}

	private static Boolean containsSame(List<SObject> records, SObject wanted) {
		for (SObject record : records) {
			if (record === wanted) {
				return true;
			}
		}
		return false;
	}
}
