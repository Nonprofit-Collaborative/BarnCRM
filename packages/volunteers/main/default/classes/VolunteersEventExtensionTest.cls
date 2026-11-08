/**
 * Dana keeps the volunteer jobs and shifts of an event in Volunteers through Core's event
 * volunteer seam (EV-08, ADR-0177 decision 12): Events never names a Volunteers object, so the
 * event is only its record identifier kept as text on the job, and Core finds this class by name.
 */
@IsTest(testFor='ApexClass:VolunteersEventExtension')
private class VolunteersEventExtensionTest {
	private static final String EVENT_KEY = 'a01000000000001AAA';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(VolunteersTestData.ADMIN);
	}

	private static User coordinator() {
		return TestUsers.adminWith(VolunteersTestData.ADMIN);
	}

	@IsTest
	static void coreFindsTheExtensionByNameAndKeepsTheEventKey() {
		System.runAs(coordinator()) {
			Assert.isTrue(EventVolunteerExtensions.isAvailable(), 'Volunteers is installed');
			Id jobId = EventVolunteerExtensions.createJob(
				EVENT_KEY,
				'Registration Desk',
				'Greet people'
			);
			Volunteer_Job__c job = [
				SELECT Name, Event_Key__c, Active__c, Description__c
				FROM Volunteer_Job__c
				WHERE Id = :jobId
			];
			Assert.areEqual(EVENT_KEY, job.Event_Key__c);
			Assert.isTrue(job.Active__c);
			Assert.areEqual('Greet people', job.Description__c);
		}
	}

	@IsTest
	static void listsTheEventsJobsWithShiftsInTimeOrder() {
		System.runAs(coordinator()) {
			Datetime start = Datetime.now().addDays(30);
			Id desk = EventVolunteerExtensions.createJob(EVENT_KEY, 'Registration Desk', null);
			EventVolunteerExtensions.createJob(EVENT_KEY, 'AV Help', null);
			EventVolunteerExtensions.createJob('a01000000000002AAA', 'Other Event Job', null);
			insert as user new Volunteer_Job__c(Name = 'Pantry Sort');
			EventVolunteerExtensions.createShift(desk, start.addHours(4), start.addHours(8), 3);
			EventVolunteerExtensions.createShift(desk, start, start.addHours(4), null);

			List<EventVolunteerJob> jobs = EventVolunteerExtensions.jobsFor(EVENT_KEY);
			Assert.areEqual(2, jobs.size(), 'Only this event, only event jobs');
			Assert.areEqual('AV Help', jobs[0].name);
			Assert.areEqual('Registration Desk', jobs[1].name);
			Assert.areEqual(2, jobs[1].shifts.size());
			Assert.isTrue(
				jobs[1].shifts[0].startTime < jobs[1].shifts[1].startTime,
				'In time order'
			);
			Assert.areEqual(1, jobs[1].shifts[0].needed, 'A shift with no number needs one person');
			Assert.areEqual(3, jobs[1].shifts[1].needed);
			Assert.areEqual('Open', jobs[1].shifts[0].status);
			Assert.areEqual(0, jobs[1].shifts[0].filled);
		}
	}

	@IsTest
	static void nothingIsListedWithoutAnEventKey() {
		System.runAs(coordinator()) {
			Assert.isTrue(new VolunteersEventExtension().jobsFor(null).isEmpty());
			Assert.isTrue(new VolunteersEventExtension().jobsFor(' ').isEmpty());
		}
	}

	@IsTest
	static void aShiftThatEndsBeforeItStartsIsRefused() {
		System.runAs(coordinator()) {
			Id desk = EventVolunteerExtensions.createJob(EVENT_KEY, 'Registration Desk', null);
			Datetime start = Datetime.now().addDays(30);
			try {
				EventVolunteerExtensions.createShift(desk, start.addHours(2), start, 2);
				Assert.fail('The shift rule still applies');
			} catch (DmlException refused) {
				Assert.areEqual(
					0,
					[SELECT COUNT() FROM Volunteer_Shift__c WHERE Volunteer_Job__c = :desk]
				);
			}
		}
	}
}
