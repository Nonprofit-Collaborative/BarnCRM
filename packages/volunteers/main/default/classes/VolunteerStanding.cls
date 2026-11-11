/**
 * Standing sign-ups (V-16, canonical model R-VU9): a sign-up with Standing checked on a shift of
 * a recurring schedule books the same person, group size and group name on every later Open
 * shift of that schedule they have no sign-up on. It runs when a schedule creates shifts and
 * when a sign-up becomes standing. The person's latest sign-up on the schedule decides: the
 * booking continues while that one is Standing and not Cancelled.
 *
 * System mode: the nightly schedule run and a coordinator's save both book for a person the
 * schedule already holds, and each copy goes through the sign-up rules (one per shift, the
 * waitlist, the minors check).
 */
public inherited sharing class VolunteerStanding {
	private static final String LOG_CONTEXT = 'VolunteerStanding.extend';
	/** Copies made here are themselves standing; their own save must not start another pass. */
	private static Boolean extending = false;

	/** After save: extends the schedules of the sign-ups that became standing. */
	public static void extendFor(
		List<Volunteer_Signup__c> signups,
		Map<Id, Volunteer_Signup__c> previousById
	) {
		if (extending) {
			return;
		}
		Set<Id> shiftIds = new Set<Id>();
		for (Volunteer_Signup__c signup : signups) {
			Volunteer_Signup__c previous = previousById == null
				? null
				: previousById.get(signup.Id);
			if (signup.Standing__c == true && (previous == null || previous.Standing__c != true)) {
				shiftIds.add(signup.Volunteer_Shift__c);
			}
		}
		if (shiftIds.isEmpty()) {
			return;
		}
		Set<Id> scheduleIds = new Set<Id>();
		for (Volunteer_Shift__c shift : [
			SELECT Shift_Schedule__c
			FROM Volunteer_Shift__c
			WHERE Id IN :shiftIds AND Shift_Schedule__c != NULL
			WITH SYSTEM_MODE
		]) {
			scheduleIds.add(shift.Shift_Schedule__c);
		}
		extend(scheduleIds);
	}

	/** Books standing people on the later Open shifts of these schedules. Returns how many. */
	public static Integer extend(Set<Id> scheduleIds) {
		scheduleIds.remove(null);
		if (scheduleIds.isEmpty()) {
			return 0;
		}
		Datetime now = Datetime.now();
		Map<Id, List<Volunteer_Shift__c>> comingBySchedule = new Map<Id, List<Volunteer_Shift__c>>();
		for (Volunteer_Shift__c shift : [
			SELECT Id, Shift_Schedule__c, Start_Time__c
			FROM Volunteer_Shift__c
			WHERE Shift_Schedule__c IN :scheduleIds AND Status__c = 'Open' AND Start_Time__c > :now
			WITH SYSTEM_MODE
			ORDER BY Start_Time__c
			LIMIT 5000
		]) {
			if (!comingBySchedule.containsKey(shift.Shift_Schedule__c)) {
				comingBySchedule.put(shift.Shift_Schedule__c, new List<Volunteer_Shift__c>());
			}
			comingBySchedule.get(shift.Shift_Schedule__c).add(shift);
		}
		if (comingBySchedule.isEmpty()) {
			return 0;
		}
		Set<Id> busySchedules = comingBySchedule.keySet();
		// Latest first, so the first row met for a person on a schedule is the one that decides.
		Map<String, Volunteer_Signup__c> latest = new Map<String, Volunteer_Signup__c>();
		Set<String> booked = new Set<String>();
		for (Volunteer_Signup__c signup : [
			SELECT
				Contact__c,
				Account__c,
				Status__c,
				Standing__c,
				Group_Size__c,
				Group_Name__c,
				Volunteer_Shift__c,
				Volunteer_Shift__r.Shift_Schedule__c,
				Volunteer_Shift__r.Start_Time__c
			FROM Volunteer_Signup__c
			WHERE Volunteer_Shift__r.Shift_Schedule__c IN :busySchedules
			WITH SYSTEM_MODE
			ORDER BY Volunteer_Shift__r.Start_Time__c DESC
			LIMIT 20000
		]) {
			Id person = signup.Contact__c != null ? signup.Contact__c : signup.Account__c;
			if (person == null) {
				continue;
			}
			booked.add(person + ':' + signup.Volunteer_Shift__c);
			String key = signup.Volunteer_Shift__r.Shift_Schedule__c + ':' + person;
			if (!latest.containsKey(key)) {
				latest.put(key, signup);
			}
		}
		List<Volunteer_Signup__c> copies = new List<Volunteer_Signup__c>();
		for (Volunteer_Signup__c last : latest.values()) {
			if (
				last.Standing__c != true ||
				last.Status__c == VolunteerSignupService.STATUS_CANCELLED
			) {
				continue;
			}
			Id person = last.Contact__c != null ? last.Contact__c : last.Account__c;
			for (
				Volunteer_Shift__c shift : comingBySchedule.get(
					last.Volunteer_Shift__r.Shift_Schedule__c
				)
			) {
				if (
					shift.Start_Time__c > last.Volunteer_Shift__r.Start_Time__c &&
					!booked.contains(person + ':' + shift.Id)
				) {
					copies.add(
						new Volunteer_Signup__c(
							Volunteer_Shift__c = shift.Id,
							Contact__c = last.Contact__c,
							Account__c = last.Contact__c == null ? last.Account__c : null,
							Status__c = VolunteerCapacity.STATUS_SIGNED_UP,
							Standing__c = true,
							Group_Size__c = last.Group_Size__c,
							Group_Name__c = last.Group_Name__c
						)
					);
				}
			}
		}
		return save(copies);
	}

	private static Integer save(List<Volunteer_Signup__c> copies) {
		if (copies.isEmpty()) {
			return 0;
		}
		Integer saved = 0;
		extending = true;
		try {
			for (
				Database.SaveResult result : Database.insert(copies, false, AccessLevel.SYSTEM_MODE)
			) {
				if (result.isSuccess()) {
					saved++;
				} else {
					ErrorLogger.logMessage(
						result.getErrors()[0].getMessage(),
						LOG_CONTEXT,
						'Warning'
					);
				}
			}
		} finally {
			extending = false;
		}
		return saved;
	}
}
