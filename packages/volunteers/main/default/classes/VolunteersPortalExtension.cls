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

	private static String signUp(Id personId, Id shiftId) {
		List<Volunteer_Shift__c> shifts = [
			SELECT Id, Status__c, Start_Time__c, Volunteers_Needed__c, Volunteer_Job__r.Active__c
			FROM Volunteer_Shift__c
			WHERE Id = :shiftId
			WITH SYSTEM_MODE
			FOR UPDATE
		];
		// The shift stays locked until this sign-up is saved, so two arriving at once are
		// counted one after the other and the last place is never given twice.
		if (shifts.isEmpty()) {
			throw new System.QueryException('The shift is gone');
		}
		Volunteer_Shift__c shift = shifts[0];
		if (
			shift.Status__c != 'Open' ||
			shift.Volunteer_Job__r.Active__c != true ||
			shift.Start_Time__c == null ||
			shift.Start_Time__c < Datetime.now()
		) {
			return BarnHelp.text('Volunteers', 'Volunteers_Portal_ShiftClosed');
		}
		// Counted now, not read from Slots Filled, which a roll-up brings up to date a moment later.
		Integer filled = [
			SELECT COUNT()
			FROM Volunteer_Signup__c
			WHERE Volunteer_Shift__c = :shiftId AND Status__c != 'Cancelled'
			WITH SYSTEM_MODE
		];
		if (shift.Volunteers_Needed__c != null && filled >= shift.Volunteers_Needed__c) {
			return BarnHelp.text('Volunteers', 'Volunteers_Portal_ShiftFull');
		}
		List<Volunteer_Signup__c> existing = [
			SELECT Id, Status__c
			FROM Volunteer_Signup__c
			WHERE Volunteer_Shift__c = :shiftId AND Contact__c = :personId
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (
			!existing.isEmpty() && existing[0].Status__c != VolunteerSignupService.STATUS_CANCELLED
		) {
			return BarnHelp.text('Volunteers', 'Volunteers_Portal_AlreadySignedUp');
		}
		if (existing.isEmpty()) {
			insert as system new Volunteer_Signup__c(
				Volunteer_Shift__c = shiftId,
				Contact__c = personId,
				Status__c = 'Signed up'
			);
		} else {
			// A cancelled sign-up is reopened: a second row for the same shift is refused.
			existing[0].Status__c = 'Signed up';
			update as system existing[0];
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
