/**
 * Shift capacity (V-14, R-VU8), group and standing sign-ups (V-16, R-VU9) and self-booking
 * (`VolunteerBooking`): a full shift refuses or waitlists, a group takes its size, a cancellation
 * moves the oldest waiting booking up, and a standing booking continues on the schedule's later
 * shifts.
 */
@IsTest(
	testFor='ApexClass:VolunteerCapacity, ApexClass:VolunteerBooking, ApexClass:VolunteerStanding, ApexClass:VolunteerSignupTriggerHandler, ApexClass:VolunteerShiftTriggerHandler, ApexClass:VolunteersPortalExtension, ApexTrigger:VolunteerSignupTrigger'
)
private class VolunteerWaitlistTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			VolunteersTestData.contacts(4);
			Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
			Volunteer_Shift__c shift = VolunteersTestData.newShift(
				job.Id,
				Datetime.now().addDays(7),
				3
			);
			shift.Volunteers_Needed__c = 2;
			insert shift;
		}
	}

	private static User admin() {
		return TestUsers.adminWith(VolunteersTestData.ADMIN);
	}

	private static void waitlist(Boolean enabled) {
		OrgSettingsSystemWriter.save(
			Volunteer_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Volunteer_Settings__c.Waitlist_Enabled__c => enabled
			}
		);
		SettingsService.clearCaches();
	}

	private static List<Contact> people() {
		return [SELECT Id FROM Contact WITH SYSTEM_MODE ORDER BY LastName];
	}

	private static Volunteer_Shift__c theShift() {
		return [
			SELECT Id, Volunteer_Job__c, Volunteers_Needed__c
			FROM Volunteer_Shift__c
			WITH SYSTEM_MODE
			LIMIT 1
		];
	}

	private static String statusOf(Id signupId) {
		return [SELECT Status__c FROM Volunteer_Signup__c WHERE Id = :signupId WITH SYSTEM_MODE]
		.Status__c;
	}

	@IsTest
	static void aFullShiftIsRefusedWhileTheWaitlistIsOff() {
		System.runAs(admin()) {
			List<Contact> people = people();
			Id shiftId = theShift().Id;

			Test.startTest();
			String first = VolunteerBooking.book(people[0].Id, shiftId, 2, 'Rivera family', false);
			String again = VolunteerBooking.book(people[0].Id, shiftId, 1, null, false);
			String full = VolunteerBooking.book(people[1].Id, shiftId, 1, null, false);
			String overTarget = VolunteerBooking.book(people[1].Id, shiftId, 1, null, true);
			Test.stopTest();

			Assert.areEqual(VolunteerBooking.SIGNED_UP, first, 'A group of two fits two places.');
			Assert.areEqual(VolunteerBooking.ALREADY, again, 'One sign-up per person per shift.');
			Assert.areEqual(VolunteerBooking.FULL, full, 'The group took both places.');
			Assert.areEqual(
				VolunteerBooking.SIGNED_UP,
				overTarget,
				'A form already sent is booked (R-VS4).'
			);
			Volunteer_Signup__c family = [
				SELECT Group_Size__c, Group_Name__c, Status__c
				FROM Volunteer_Signup__c
				WHERE Contact__c = :people[0].Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, family.Group_Size__c, 'The group size is kept.');
			Assert.areEqual('Rivera family', family.Group_Name__c, 'The group name is kept.');
		}
	}

	@IsTest
	static void aClosedShiftBooksNobody() {
		System.runAs(admin()) {
			Volunteer_Shift__c shift = theShift();
			shift.Status__c = 'Cancelled';
			update shift;

			Test.startTest();
			String result = VolunteerBooking.book(people()[0].Id, shift.Id, 1, null, true);
			Test.stopTest();

			Assert.areEqual(
				VolunteerBooking.CLOSED,
				result,
				'Only an Open shift still to come is booked.'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Volunteer_Signup__c WITH SYSTEM_MODE],
				'Nothing saved.'
			);
		}
	}

	@IsTest
	static void aBulkSaveIntoAFullShiftWaitlistsTheRest() {
		System.runAs(admin()) {
			waitlist(true);
			Id shiftId = theShift().Id;
			List<Volunteer_Signup__c> signups = new List<Volunteer_Signup__c>();
			for (Contact person : people()) {
				signups.add(VolunteersTestData.newSignup(shiftId, person.Id));
			}

			Test.startTest();
			insert signups;
			Test.stopTest();

			Assert.areEqual('Signed up', statusOf(signups[0].Id), 'First place.');
			Assert.areEqual('Signed up', statusOf(signups[1].Id), 'Second place.');
			Assert.areEqual(
				'Waitlisted',
				statusOf(signups[2].Id),
				'Past Volunteers Needed, in order.'
			);
			Assert.areEqual(
				'Waitlisted',
				statusOf(signups[3].Id),
				'Past Volunteers Needed, in order.'
			);
		}
	}

	@IsTest
	static void aCancellationOrMorePlacesMovesTheOldestUp() {
		System.runAs(admin()) {
			waitlist(true);
			Volunteer_Shift__c shift = theShift();
			List<Contact> people = people();
			List<String> results = new List<String>();
			for (Contact person : people) {
				results.add(VolunteerBooking.book(person.Id, shift.Id, 1, null, false));
			}
			Assert.areEqual(
				VolunteerBooking.WAITLISTED,
				results[2],
				'A full shift waitlists when on.'
			);
			Map<Id, Volunteer_Signup__c> byPerson = new Map<Id, Volunteer_Signup__c>();
			for (Volunteer_Signup__c signup : [
				SELECT Id, Contact__c
				FROM Volunteer_Signup__c
				WITH SYSTEM_MODE
			]) {
				byPerson.put(signup.Contact__c, signup);
			}

			Test.startTest();
			update new Volunteer_Signup__c(
				Id = byPerson.get(people[0].Id).Id,
				Status__c = 'Cancelled'
			);
			String afterCancel = statusOf(byPerson.get(people[2].Id).Id);
			shift.Volunteers_Needed__c = 3;
			update shift;
			Test.stopTest();

			Assert.areEqual('Signed up', afterCancel, 'The oldest waiting takes the freed place.');
			Assert.areEqual(
				'Signed up',
				statusOf(byPerson.get(people[3].Id).Id),
				'A raised need moves the next up.'
			);
		}
	}

	@IsTest
	static void theWaitlistMessageReachesThePortal() {
		System.runAs(admin()) {
			waitlist(true);
			Id shiftId = theShift().Id;
			List<Contact> people = people();
			VolunteersPortalExtension portal = new VolunteersPortalExtension();
			portal.run(VolunteersPortalExtension.SIGN_UP, people[0].Id, shiftId);
			portal.run(VolunteersPortalExtension.SIGN_UP, people[1].Id, shiftId);

			Test.startTest();
			String message = portal.run(VolunteersPortalExtension.SIGN_UP, people[2].Id, shiftId);
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Volunteers', 'Volunteers_Portal_Waitlisted'),
				message,
				'Told they wait.'
			);
		}
	}

	@IsTest
	static void aStandingSignupContinuesOnLaterShifts() {
		System.runAs(admin()) {
			Volunteer_Job__c job = [SELECT Id FROM Volunteer_Job__c WITH SYSTEM_MODE LIMIT 1];
			Shift_Schedule__c schedule = VolunteersTestData.newSchedule(
				job.Id,
				'Saturday',
				Date.today()
			);
			AutomationControl.bypass('Shift_Schedule_Rules');
			insert schedule;
			AutomationControl.clearBypass('Shift_Schedule_Rules');
			List<Volunteer_Shift__c> weekly = new List<Volunteer_Shift__c>();
			for (Integer week = 1; week <= 3; week++) {
				Volunteer_Shift__c shift = VolunteersTestData.newShift(
					job.Id,
					Datetime.now().addDays(7 * week),
					3
				);
				shift.Shift_Schedule__c = schedule.Id;
				weekly.add(shift);
			}
			insert weekly;
			Volunteer_Signup__c standing = VolunteersTestData.newSignup(
				weekly[0].Id,
				people()[0].Id
			);
			standing.Standing__c = true;
			standing.Group_Size__c = 2;

			Test.startTest();
			insert standing;
			Test.stopTest();

			List<Volunteer_Signup__c> copies = [
				SELECT Volunteer_Shift__c, Standing__c, Group_Size__c
				FROM Volunteer_Signup__c
				WHERE Id != :standing.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, copies.size(), 'Booked on both later shifts of the schedule.');
			for (Volunteer_Signup__c copy : copies) {
				Assert.isTrue(copy.Standing__c, 'A copy is itself standing.');
				Assert.areEqual(2, copy.Group_Size__c, 'The group size carries over.');
			}
			Assert.areEqual(
				0,
				VolunteerStanding.extend(new Set<Id>{ schedule.Id }),
				'Never booked twice.'
			);
		}
	}
}
