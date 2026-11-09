/**
 * Sam signs in to the volunteer portal, signs up for an open shift and cancels it (PB-03). The
 * actions act only for the verified person, refuse a closed, full or past shift, and never make
 * a second sign-up for the same shift.
 */
@IsTest(testFor='ApexClass:VolunteersPortalExtension')
private class VolunteersPortalExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(VolunteersTestData.ADMIN);
	}

	private static User coordinator() {
		return TestUsers.adminWith(VolunteersTestData.ADMIN);
	}

	private static Volunteer_Shift__c futureShift(Integer needed) {
		Volunteer_Job__c job = VolunteersTestData.job('Pantry Sort');
		Volunteer_Shift__c shift = VolunteersTestData.newShift(
			job.Id,
			Datetime.now().addDays(7),
			3
		);
		shift.Volunteers_Needed__c = needed;
		insert shift;
		return shift;
	}

	private static List<Volunteer_Signup__c> signupsOf(Id shiftId) {
		return [
			SELECT Id, Contact__c, Status__c
			FROM Volunteer_Signup__c
			WHERE Volunteer_Shift__c = :shiftId
		];
	}

	@IsTest
	static void coreFindsBothActionsByName() {
		System.runAs(coordinator()) {
			Assert.isTrue(
				PortalActionExtensions.forAction(
					'Volunteers.SignUp'
				) instanceof VolunteersPortalExtension,
				'Sign up is offered'
			);
			Assert.isTrue(
				PortalActionExtensions.forAction(
					'Volunteers.CancelSignup'
				) instanceof VolunteersPortalExtension,
				'Cancel is offered'
			);
		}
	}

	@IsTest
	static void signsThePersonUpOnceAndReopensACancelledSignup() {
		System.runAs(coordinator()) {
			Contact sam = VolunteersTestData.contact('Sam', null);
			Volunteer_Shift__c shift = futureShift(3);
			VolunteersPortalExtension extension = new VolunteersPortalExtension();

			Test.startTest();
			String first = extension.run(VolunteersPortalExtension.SIGN_UP, sam.Id, shift.Id);
			String second = extension.run(VolunteersPortalExtension.SIGN_UP, sam.Id, shift.Id);
			List<Volunteer_Signup__c> signups = signupsOf(shift.Id);
			String cancelled = extension.run(
				VolunteersPortalExtension.CANCEL,
				sam.Id,
				signups[0].Id
			);
			String again = extension.run(VolunteersPortalExtension.SIGN_UP, sam.Id, shift.Id);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Volunteers', 'Volunteers_Portal_SignedUp'), first);
			Assert.areEqual(
				BarnHelp.text('Volunteers', 'Volunteers_Portal_AlreadySignedUp'),
				second
			);
			Assert.areEqual(1, signups.size(), 'One sign-up, never two');
			Assert.areEqual(sam.Id, signups[0].Contact__c, 'For the verified person');
			Assert.areEqual(BarnHelp.text('Volunteers', 'Volunteers_Portal_Cancelled'), cancelled);
			Assert.areEqual(BarnHelp.text('Volunteers', 'Volunteers_Portal_SignedUp'), again);
			Assert.areEqual(1, signupsOf(shift.Id).size(), 'The cancelled row was reopened');
			Assert.areEqual('Signed up', signupsOf(shift.Id)[0].Status__c);
		}
	}

	@IsTest
	static void refusesAFullClosedOrPastShift() {
		System.runAs(coordinator()) {
			List<Contact> people = VolunteersTestData.contacts(2);
			Volunteer_Shift__c oneSlot = futureShift(1);
			Volunteer_Shift__c past = VolunteersTestData.newShift(
				oneSlot.Volunteer_Job__c,
				Datetime.now().addDays(-2),
				2
			);
			insert past;
			Volunteer_Shift__c closed = futureShift(2);
			closed.Status__c = 'Cancelled';
			update closed;
			VolunteersPortalExtension extension = new VolunteersPortalExtension();

			Test.startTest();
			extension.run(VolunteersPortalExtension.SIGN_UP, people[0].Id, oneSlot.Id);
			String full = extension.run(
				VolunteersPortalExtension.SIGN_UP,
				people[1].Id,
				oneSlot.Id
			);
			String pastMessage = extension.run(
				VolunteersPortalExtension.SIGN_UP,
				people[1].Id,
				past.Id
			);
			String closedMessage = extension.run(
				VolunteersPortalExtension.SIGN_UP,
				people[1].Id,
				closed.Id
			);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Volunteers', 'Volunteers_Portal_ShiftFull'), full);
			Assert.areEqual(
				BarnHelp.text('Volunteers', 'Volunteers_Portal_ShiftClosed'),
				pastMessage
			);
			Assert.areEqual(
				BarnHelp.text('Volunteers', 'Volunteers_Portal_ShiftClosed'),
				closedMessage
			);
			Assert.areEqual(1, signupsOf(oneSlot.Id).size(), 'Only the first person got the slot');
			Assert.isTrue(signupsOf(past.Id).isEmpty(), 'Nothing on a past shift');
		}
	}

	@IsTest
	static void theLastPlaceIsGivenOnceEvenToSomeoneReturning() {
		System.runAs(coordinator()) {
			List<Contact> people = VolunteersTestData.contacts(2);
			Volunteer_Shift__c oneSlot = futureShift(1);
			VolunteersPortalExtension extension = new VolunteersPortalExtension();

			Test.startTest();
			extension.run(VolunteersPortalExtension.SIGN_UP, people[0].Id, oneSlot.Id);
			extension.run(
				VolunteersPortalExtension.CANCEL,
				people[0].Id,
				signupsOf(oneSlot.Id)[0].Id
			);
			String taken = extension.run(
				VolunteersPortalExtension.SIGN_UP,
				people[1].Id,
				oneSlot.Id
			);
			String returning = extension.run(
				VolunteersPortalExtension.SIGN_UP,
				people[0].Id,
				oneSlot.Id
			);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Volunteers', 'Volunteers_Portal_SignedUp'), taken);
			Assert.areEqual(
				BarnHelp.text('Volunteers', 'Volunteers_Portal_ShiftFull'),
				returning,
				'A cancelled sign-up is not reopened into a full shift'
			);
			Integer active = 0;
			for (Volunteer_Signup__c signup : signupsOf(oneSlot.Id)) {
				if (signup.Status__c != VolunteerSignupService.STATUS_CANCELLED) {
					active++;
				}
			}
			Assert.areEqual(1, active, 'One place, one person');
		}
	}

	@IsTest
	static void aPersonCancelsOnlyTheirOwnSignup() {
		System.runAs(coordinator()) {
			List<Contact> people = VolunteersTestData.contacts(2);
			Volunteer_Shift__c shift = futureShift(3);
			Volunteer_Signup__c theirs = VolunteersTestData.newSignup(shift.Id, people[0].Id);
			insert theirs;
			VolunteersPortalExtension extension = new VolunteersPortalExtension();

			Test.startTest();
			try {
				extension.run(VolunteersPortalExtension.CANCEL, people[1].Id, theirs.Id);
				Assert.fail('Another person cannot cancel it');
			} catch (System.QueryException refused) {
				Assert.isNotNull(refused.getMessage(), 'Refused');
			}
			try {
				extension.run('Volunteers.Nope', people[0].Id, theirs.Id);
				Assert.fail('An unknown action is refused');
			} catch (System.IllegalArgumentException refused) {
				Assert.isNotNull(refused.getMessage(), 'Refused');
			}
			Test.stopTest();

			Assert.areEqual('Signed up', signupsOf(shift.Id)[0].Status__c, 'Untouched');
		}
	}
}
