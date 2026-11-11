/**
 * The volunteer portal's two actions (PB-03; ADR-0185 decision 9 and ADR-0191
 * `0191-portal-templates-volunteer-speaker-donor.md`): `Volunteers.SignUp` on an open shift and `Volunteers.CancelSignup` on the person's own sign-up. Core finds this
 * class by name (`PortalActionExtensions.EXTENSION_CLASSES`); Portal Builder has already checked
 * that the record is on the verified person's page, and the person is the only one acted for.
 *
 * `without sharing` and system mode (ADR-0021): the portal's integration user has no object
 * access. Every write names the verified person, never one the caller supplies, and goes through
 * the same triggers as a coordinator's, so the one-sign-up-per-shift rule still holds.
 *
 * `@NamespaceAccessible` with a public no-argument constructor because Core resolves it by name
 * under ADR-0017.
 */
@NamespaceAccessible
public without sharing class VolunteersPortalExtension implements PortalActionExtension {
	public static final String SIGN_UP = 'Volunteers.SignUp';
	public static final String CANCEL = 'Volunteers.CancelSignup';

	@NamespaceAccessible
	public VolunteersPortalExtension() {
		return;
	}

	public Set<String> actionNames() {
		return new Set<String>{ SIGN_UP, CANCEL };
	}

	public String run(String actionName, Id personId, Id recordId) {
		if (personId == null || recordId == null) {
			throw new System.IllegalArgumentException('A person and a record are needed');
		}
		if (actionName == SIGN_UP) {
			return signUp(personId, recordId);
		}
		if (actionName == CANCEL) {
			return cancel(personId, recordId);
		}
		throw new System.IllegalArgumentException('Unknown action ' + actionName);
	}

	/** Books through `VolunteerBooking`, as a public form does: a full shift waitlists when on. */
	private static String signUp(Id personId, Id shiftId) {
		String outcome = VolunteerBooking.book(personId, shiftId, 1, null, false);
		if (outcome == VolunteerBooking.WAITLISTED) {
			return BarnHelp.text('Volunteers', 'Volunteers_Portal_Waitlisted');
		}
		if (outcome == VolunteerBooking.ALREADY) {
			return BarnHelp.text('Volunteers', 'Volunteers_Portal_AlreadySignedUp');
		}
		if (outcome == VolunteerBooking.CLOSED) {
			return BarnHelp.text('Volunteers', 'Volunteers_Portal_ShiftClosed');
		}
		if (outcome == VolunteerBooking.FULL) {
			return BarnHelp.text('Volunteers', 'Volunteers_Portal_ShiftFull');
		}
		return BarnHelp.text('Volunteers', 'Volunteers_Portal_SignedUp');
	}

	private static String cancel(Id personId, Id signupId) {
		List<Volunteer_Signup__c> signups = [
			SELECT Id, Status__c, Volunteer_Shift__r.Start_Time__c
			FROM Volunteer_Signup__c
			WHERE Id = :signupId AND Contact__c = :personId
			WITH SYSTEM_MODE
		];
		if (signups.isEmpty()) {
			throw new System.QueryException('The sign-up is not this person\'s');
		}
		Volunteer_Signup__c signup = signups[0];
		Boolean cancellable =
			(signup.Status__c == 'Signed up' || signup.Status__c == 'Confirmed') &&
			signup.Volunteer_Shift__r.Start_Time__c > Datetime.now();
		if (!cancellable) {
			return BarnHelp.text('Volunteers', 'Volunteers_Portal_CannotCancel');
		}
		signup.Status__c = VolunteerSignupService.STATUS_CANCELLED;
		update as system signup;
		return BarnHelp.text('Volunteers', 'Volunteers_Portal_Cancelled');
	}
}
