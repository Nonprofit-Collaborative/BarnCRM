/**
 * Dana opens an event's Volunteers section: with Volunteers absent it shows nothing, with
 * Volunteers installed she adds a job and a shift for the event through Core's seam (EV-08).
 * Events cannot name Volunteers, so what it can check depends on the org, and both are covered.
 */
@IsTest(testFor='ApexClass:EventVolunteersController')
private class EventVolunteersControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staffWithVolunteers() {
		return TestUsers.withPermissionSets(
			new List<String>{ TestUsers.CORE_ADMIN, EventsAccessSync.ADMIN_SET, 'Volunteers_Admin' }
		);
	}

	private static Event__c conference() {
		Datetime start = Datetime.now().addDays(30);
		Event__c record = new Event__c(
			Name = 'Community Dreamin',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8)
		);
		insert as user record;
		return record;
	}

	@IsTest
	static void showsNothingWhenNoModuleKeepsVolunteerJobs() {
		System.runAs(staff()) {
			Event__c event = conference();
			EventVolunteersController.Volunteers result = EventVolunteersController.getVolunteers(
				event.Id
			);
			Assert.areEqual(EventVolunteerExtensions.isAvailable(), result.available);
			if (!result.available) {
				Assert.isTrue(result.jobs.isEmpty());
				Assert.isNull(result.eventStart, 'Nothing is read when there is no panel');
			}
		}
	}

	@IsTest
	static void addsAJobAndAShiftWhenVolunteersIsInstalled() {
		if (!EventVolunteerExtensions.isAvailable()) {
			return;
		}
		System.runAs(staffWithVolunteers()) {
			Event__c event = conference();
			String jobId = EventVolunteersController.addJob(
				event.Id,
				' Registration Desk ',
				'Greet'
			);
			Assert.isNotNull(jobId);
			EventVolunteersController.addShift(
				event.Id,
				jobId,
				event.Start__c,
				event.Start__c.addHours(4),
				3
			);
			EventVolunteersController.Volunteers result = EventVolunteersController.getVolunteers(
				event.Id
			);
			Assert.isTrue(result.available);
			Assert.areEqual(1, result.jobs.size());
			Assert.areEqual('Registration Desk', result.jobs[0].name);
			Assert.areEqual(1, result.jobs[0].shifts.size());
			Assert.areEqual(3, result.jobs[0].shifts[0].needed);
			Assert.isNotNull(result.eventEnd);
		}
	}

	@IsTest
	static void refusesABlankNameAndABadShift() {
		System.runAs(staff()) {
			Event__c event = conference();
			try {
				EventVolunteersController.addJob(event.Id, '  ', null);
				Assert.fail('A job needs a name');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused);
			}
			Datetime start = event.Start__c;
			List<Integer> needs = new List<Integer>{ 0, null, 2 };
			List<Datetime> ends = new List<Datetime>{ start.addHours(1), start.addHours(1), start };
			for (Integer i = 0; i < needs.size(); i++) {
				try {
					EventVolunteersController.addShift(
						event.Id,
						event.Id,
						start,
						ends[i],
						needs[i]
					);
					Assert.fail('A bad shift is refused: ' + i);
				} catch (AuraHandledException refused) {
					Assert.isNotNull(refused);
				}
			}
		}
	}
}
