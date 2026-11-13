/**
 * Summit Events registrants land in BarnCRM people without duplicates, each Summit instance
 * becomes one event, a registration is imported once, and nothing runs without Summit (EV-10).
 * Summit is not installed in a test org, so its records are given as maps of field names.
 */
@IsTest(
	testFor='ApexClass:SummitEventsAdapter, ApexClass:SummitEventsBatch, ApexClass:SummitEventsScheduler, ApexClass:EventsNightlyJobProvider'
)
private class SummitEventsAdapterTest {
	private static final String INSTANCE_ID = 'a0SUMMITINSTANCE01';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	/** One Summit instance next week, given as Summit's own field names. */
	private static void summitInstance() {
		SummitEventsAdapter.instancesForTest = new Map<String, Map<String, Object>>{
			INSTANCE_ID => new Map<String, Object>{
				'id' => INSTANCE_ID,
				SummitEventsAdapter.I_TITLE => 'Fall Open House',
				SummitEventsAdapter.I_START_DATE => Date.today().addDays(5),
				SummitEventsAdapter.I_START_TIME => Time.newInstance(18, 0, 0, 0),
				SummitEventsAdapter.I_END_TIME => Time.newInstance(20, 0, 0, 0)
			}
		};
	}

	/** A Summit registration as the import reads it from Summit's fields. */
	private static Map<String, Object> row(
		String id,
		String status,
		String first,
		String last,
		String email
	) {
		return SummitEventsAdapter.registrationRow(
			new Map<String, Object>{
				'id' => id,
				SummitEventsAdapter.R_INSTANCE => INSTANCE_ID,
				SummitEventsAdapter.R_STATUS => status,
				SummitEventsAdapter.R_FIRST => first,
				SummitEventsAdapter.R_LAST => last,
				SummitEventsAdapter.R_EMAIL => email
			}
		);
	}

	@IsTest
	static void importsRegistrantsWithoutDuplicates() {
		System.runAs(staff()) {
			Contact jane = TestDataFactory.person(
				new Contact(FirstName = 'Jane', LastName = 'Doe', Email = 'jane@example.org')
			);
			insert as user jane;
			Contact sam = TestDataFactory.person(new Contact(FirstName = 'Sam', LastName = 'Lee'));
			insert as user sam;
			summitInstance();
			Map<String, Object> samRow = row('REG2', 'Attended', null, null, null);
			samRow.put('contactId', sam.Id);

			Test.startTest();
			Integer imported = SummitEventsAdapter.importRows(
				new List<Map<String, Object>>{
					row('REG1', 'Registered', 'Jane', 'Doe', 'JANE@example.org'),
					samRow,
					row('REG3', 'Started', 'Max', 'Lee', 'max@example.org'),
					row('REG4', 'Cancelled', 'Ann', 'Lee', 'ann@example.org')
				}
			);
			Integer again = SummitEventsAdapter.importRows(
				new List<Map<String, Object>>{
					row('REG1', 'Registered', 'Jane', 'Doe', 'jane@example.org')
				}
			);
			Test.stopTest();

			Assert.isTrue(imported == 2, 'Jane and Sam imported; Started and Cancelled left out');
			Assert.isTrue(again == 0, 'A registration is imported once');
			List<Event__c> events = [
				SELECT Name, Status__c, External_Key__c
				FROM Event__c
				WITH USER_MODE
			];
			Assert.areEqual(1, events.size(), 'One event for the instance');
			Assert.areEqual('Fall Open House', events[0].Name, 'Named after the instance');
			Assert.areEqual(
				'summit:' + INSTANCE_ID,
				events[0].External_Key__c,
				'Keyed by the instance'
			);
			Assert.areEqual('Open', events[0].Status__c, 'A future instance is open');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Contact WHERE LastName = 'Doe' WITH USER_MODE],
				'Jane matched by email, never duplicated'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Contact WHERE FirstName IN ('Max', 'Ann') WITH USER_MODE],
				'Nobody created for a registration left out'
			);
			Map<Id, Event_Attendee__c> byPerson = new Map<Id, Event_Attendee__c>();
			for (Event_Attendee__c attendee : [
				SELECT
					Contact__c,
					Status__c,
					Event_Registration__r.Source__c,
					Event_Registration__r.External_Key__c
				FROM Event_Attendee__c
				WITH USER_MODE
			]) {
				byPerson.put(attendee.Contact__c, attendee);
			}
			Event_Attendee__c janeSeat = byPerson.get(jane.Id);
			Assert.areEqual('Registered', janeSeat.Status__c, 'Jane registered');
			Assert.areEqual(
				'Summit Events',
				janeSeat.Event_Registration__r.Source__c,
				'Source Summit Events'
			);
			Assert.areEqual(
				'summit:REG1',
				janeSeat.Event_Registration__r.External_Key__c,
				'Keyed by the registration'
			);
			Assert.areEqual('Attended', byPerson.get(sam.Id).Status__c, 'Summit attendance kept');
			Assert.areEqual(
				jane.Id,
				SummitEventsAdapter.writtenBack.get('REG1'),
				'Jane goes back to Summit'
			);
			Assert.isFalse(
				SummitEventsAdapter.writtenBack.containsKey('REG2'),
				'Sam already had a contact'
			);
		}
	}

	@IsTest
	static void createsANewPersonWhenNobodyMatches() {
		System.runAs(staff()) {
			summitInstance();
			Test.startTest();
			Integer imported = SummitEventsAdapter.importRows(
				new List<Map<String, Object>>{ row('REG9', null, 'Rae', 'Kim', 'rae@example.org') }
			);
			Test.stopTest();
			Assert.isTrue(imported == 1, 'Imported');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Contact WHERE Email = 'rae@example.org' WITH USER_MODE],
				'A new person'
			);
		}
	}

	@IsTest
	static void countsAndLogsWhatCannotBeImported() {
		System.runAs(staff()) {
			SummitEventsAdapter.instancesForTest = new Map<String, Map<String, Object>>{
				INSTANCE_ID => new Map<String, Object>{ 'id' => INSTANCE_ID }
			};
			Test.startTest();
			Integer imported = SummitEventsAdapter.importRows(
				new List<Map<String, Object>>{ row('REG7', 'Registered', 'Lou', 'Park', null) }
			);
			Test.stopTest();
			Assert.isTrue(imported == 0, 'An instance with no start date makes no event');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Event_Registration__c WITH USER_MODE],
				'Nothing saved'
			);
		}
	}

	@IsTest
	static void readsSummitFieldsAndStatuses() {
		System.runAs(staff()) {
			Assert.areEqual('Attended', SummitEventsAdapter.attendeeStatus('Attended'), 'Attended');
			Assert.areEqual('No-Show', SummitEventsAdapter.attendeeStatus('No Show'), 'No Show');
			Assert.areEqual(
				'No-Show',
				SummitEventsAdapter.attendeeStatus('Did Not Attend'),
				'Did not attend'
			);
			Assert.areEqual(
				'Registered',
				SummitEventsAdapter.attendeeStatus('Confirmed'),
				'Confirmed'
			);
			Assert.areEqual('Registered', SummitEventsAdapter.attendeeStatus(null), 'Blank');

			Map<String, Object> instance = SummitEventsAdapter.instanceRow(
				new Map<String, Object>{
					'id' => 'X1',
					'name' => 'SEI-0001',
					SummitEventsAdapter.I_EVENT_RELATION => new Event__c(Name = 'Campus Tour'),
					SummitEventsAdapter.I_START_DATE => Date.today().addDays(-3)
				}
			);
			Assert.isNull(
				SummitEventsAdapter.instanceRow(new Map<String, Object>{ 'id' => 'X2' }),
				'No start date, no event'
			);
			Event__c past = SummitEventsAdapter.eventFrom(instance);
			Assert.areEqual('Campus Tour', past.Name, 'Named after the Summit event');
			Assert.areEqual('Completed', past.Status__c, 'A past instance is completed');
			Assert.isTrue(past.End__c > past.Start__c, 'Ends after it starts');
			Assert.areEqual('summit:X1', past.External_Key__c, 'Keyed by the instance');
		}
	}

	@IsTest
	static void doesNothingWithoutSummit() {
		System.runAs(staff()) {
			Boolean noLocator = false;
			Test.startTest();
			Id job = SummitEventsBatch.startMorning();
			List<NightlyStep> steps = new EventsNightlyJobProvider().nightlySteps();
			NightlyStep step = SummitEventsScheduler.step();
			SummitEventsBatch batch = new SummitEventsBatch();
			try {
				batch.start(null);
			} catch (Exception noSummit) {
				noLocator = true;
			}
			batch.execute(null, new List<SObject>{ new Event__c(Name = 'Not Summit') });
			batch.finish(null);
			Test.stopTest();

			Assert.isFalse(SummitEventsAdapter.isInstalled(), 'Summit is not in a test org');
			Assert.isNull(job, 'No import starts');
			Assert.isTrue(noLocator, 'Summit cannot be read where it is not installed');
			Assert.areEqual(1, steps.size(), 'No Summit step in the nightly run');
			Assert.isFalse(step.active, 'The step is inactive without Summit');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Event_Registration__c WITH USER_MODE],
				'A record that is not a Summit registration imports nothing'
			);
		}
	}
}
