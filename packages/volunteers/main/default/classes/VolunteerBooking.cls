/**
 * The one path a volunteer books themselves onto a shift: the portal's Sign Up action (PB-03,
 * `VolunteersPortalExtension`) and the public sign-up form (V-09, `VolunteerFormAttachment`).
 * The save goes through the same sign-up rules as a coordinator's (one sign-up per shift,
 * the waitlist, the minors check), so nothing is decided twice.
 *
 * `inherited sharing` with system mode reads and writes: the portal calls it as an integration
 * user with no object access (from a `without sharing` class), and Forms processing as the user
 * who processes submissions. Every write names the person the caller verified.
 */
public inherited sharing class VolunteerBooking {
	public static final String SIGNED_UP = 'Volunteers_Portal_SignedUp';
	public static final String WAITLISTED = 'Volunteers_Portal_Waitlisted';
	public static final String ALREADY = 'Volunteers_Portal_AlreadySignedUp';
	public static final String CLOSED = 'Volunteers_Portal_ShiftClosed';
	public static final String FULL = 'Volunteers_Portal_ShiftFull';
	private static final Integer MAX_GROUP = 50;

	/**
	 * Books the person on the shift and returns the help text key of what happened. A shift that
	 * is not Open, has started or whose job is inactive is closed. A full shift is refused unless
	 * the waitlist is on (the sign-up is then Waitlisted) or `overTarget` is true, as for a public
	 * form already sent, which R-VS4 allows. A cancelled sign-up of the person is reopened.
	 */
	public static String book(
		Id personId,
		Id shiftId,
		Integer groupSize,
		String groupName,
		Boolean overTarget
	) {
		List<Volunteer_Shift__c> shifts = [
			SELECT Id, Status__c, Start_Time__c, Volunteers_Needed__c, Volunteer_Job__r.Active__c
			FROM Volunteer_Shift__c
			WHERE Id = :shiftId
			WITH SYSTEM_MODE
			FOR UPDATE
		];
		// The shift stays locked until this sign-up is saved, so two arriving at once are
		// counted one after the other and the last place is never given twice.
		if (
			shifts.isEmpty() ||
			shifts[0].Status__c != 'Open' ||
			shifts[0].Volunteer_Job__r.Active__c != true ||
			shifts[0].Start_Time__c == null ||
			shifts[0].Start_Time__c < Datetime.now()
		) {
			return CLOSED;
		}
		Integer places = groupSize == null ||
			groupSize < 1 ||
			groupSize > MAX_GROUP
			? 1
			: groupSize;
		if (!overTarget && !VolunteerSettings.waitlistEnabled() && placesLeft(shifts[0]) < places) {
			return FULL;
		}
		Boolean isAccount = personId.getSObjectType() == Account.SObjectType;
		List<Volunteer_Signup__c> existing = [
			SELECT Id, Status__c
			FROM Volunteer_Signup__c
			WHERE
				Volunteer_Shift__c = :shiftId
				AND (Contact__c = :personId
				OR Account__c = :personId)
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (
			!existing.isEmpty() && existing[0].Status__c != VolunteerSignupService.STATUS_CANCELLED
		) {
			return ALREADY;
		}
		Volunteer_Signup__c signup = existing.isEmpty()
			? new Volunteer_Signup__c(
					Volunteer_Shift__c = shiftId,
					Contact__c = isAccount ? null : personId,
					Account__c = isAccount ? personId : null
			  )
			: existing[0];
		signup.Status__c = VolunteerCapacity.STATUS_SIGNED_UP;
		signup.Group_Size__c = places;
		signup.Group_Name__c = String.isBlank(groupName) ? null : groupName.trim().abbreviate(80);
		// A cancelled sign-up is reopened: a second row for the same shift is refused (R-VU2).
		upsert as system signup;
		Volunteer_Signup__c saved = [
			SELECT Status__c
			FROM Volunteer_Signup__c
			WHERE Id = :signup.Id
			WITH SYSTEM_MODE
		];
		return saved.Status__c == VolunteerCapacity.STATUS_WAITLISTED ? WAITLISTED : SIGNED_UP;
	}

	/**
	 * Places left on the shift, counted now from the sign-ups, not Slots Filled, which a roll-up
	 * brings up to date a moment later. A shift with no Volunteers Needed has no limit.
	 */
	public static Decimal placesLeft(Volunteer_Shift__c shift) {
		if (shift.Volunteers_Needed__c == null) {
			return 1000000;
		}
		Decimal taken = 0;
		for (Volunteer_Signup__c held : [
			SELECT Group_Size__c
			FROM Volunteer_Signup__c
			WHERE Volunteer_Shift__c = :shift.Id AND Status__c NOT IN ('Cancelled', 'Waitlisted')
			WITH SYSTEM_MODE
			LIMIT 10000
		]) {
			taken += WaitlistQueue.placesOf(held, 'Group_Size__c');
		}
		return shift.Volunteers_Needed__c - taken;
	}
}
