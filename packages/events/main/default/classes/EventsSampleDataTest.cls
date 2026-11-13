/**
 * The Event Management sample data set (C-10): a conference under way and a small community
 * event for Core's sample people and organizations, counted on the card, removed again with real
 * events left alone, and nothing loaded where there are no sample people. Run as a BarnCRM admin
 * holding Events Admin, the person who loads sample data.
 *
 * The set ships as EventsSampleData.json and Core's SampleDataFile loads it (D-200 S2). The
 * stages are called directly, as the other modules' tests do, because a test runs only the
 * first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class EventsSampleDataTest {
	private static final String FILE = 'EventsSampleData';
	private static final String CONFERENCE = 'Harvest Community Conference';
	private static final String COMMUNITY = 'Neighborhood Garden Night';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User admin() {
		return TestUsers.adminWith('Events_Admin');
	}

	/** Core's sample people and three of its sample organizations. */
	private static void samplePeopleAndOrganizations() {
		List<Contact> people = new List<Contact>();
		List<String> keys = new List<String>{
			'H001-1',
			'H001-2',
			'H001-3',
			'H002-1',
			'H002-2',
			'H002-3',
			'H002-4',
			'H002-5'
		};
		for (Integer i = 0; i < keys.size(); i++) {
			people.add(
				TestDataFactory.person(
					new Contact(
						FirstName = 'Sample',
						LastName = 'Person' + i,
						Email = 'sample' + i + '@example.org',
						Sample_Data__c = true,
						Sample_Data_Key__c = keys[i]
					)
				)
			);
		}
		insert people;
		List<Account> organizations = new List<Account>();
		for (String key : new List<String>{ 'O022', 'O014', 'O001' }) {
			Account organization = (Account) TestDataFactory.pastDuplicateRules(
				AccountKindsTestData.organization('Sample Org ' + key)
			);
			organization.Sample_Data__c = true;
			organization.Sample_Data_Key__c = key;
			organizations.add(organization);
		}
		insert organizations;
	}

	private static void loadEverything() {
		SampleDataFile.LoadStages stages = new SampleDataFile.LoadStages(FILE);
		for (Integer stage = 0; stage < stages.stageCount(); stage++) {
			stages.runStage(stage);
		}
	}

	private static void removeEverything() {
		SampleDataFile.RemoveStages stages = new SampleDataFile.RemoveStages(FILE);
		Integer stageCount = stages.stageCount();
		for (Integer stage = 0; stage < stageCount; stage++) {
			stages.runStage(stage);
		}
	}

	@IsTest
	static void theLoadBuildsTheConferenceAndTheCommunityEvent() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Events', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(2, module.countLoaded(), 'Two sample events are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');
			Event__c conference = [
				SELECT Id
				FROM Event__c
				WHERE Name = :CONFERENCE
				WITH SYSTEM_MODE
			];
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Event_Track__c
					WHERE Event__c = :conference.Id
					WITH SYSTEM_MODE
				],
				'Three tracks'
			);
			Assert.areEqual(
				8,
				[
					SELECT COUNT()
					FROM Event_Session__c
					WHERE Event__c = :conference.Id
					WITH SYSTEM_MODE
				],
				'Eight sessions'
			);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Event_Speaker__c
					WHERE Event__c = :conference.Id
					WITH SYSTEM_MODE
				],
				'Three speakers'
			);
			Assert.areEqual(
				6,
				[SELECT COUNT() FROM Session_Speaker__c WITH SYSTEM_MODE],
				'Speakers are placed on sessions'
			);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Ticket_Type__c
					WHERE Event__c = :conference.Id
					WITH SYSTEM_MODE
				],
				'Three ticket types'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Promo_Code__c
					WHERE Event__c = :conference.Id
					WITH SYSTEM_MODE
				],
				'One promo code'
			);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Event_Sponsor__c
					WHERE Event__c = :conference.Id
					WITH SYSTEM_MODE
				],
				'Three sponsors'
			);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Sponsorship_Level__c
					WHERE Event__c = :conference.Id
					WITH SYSTEM_MODE
				],
				'Three levels'
			);
			Assert.areEqual(
				4,
				[SELECT COUNT() FROM Sponsor_Deliverable__c WITH SYSTEM_MODE],
				'Four deliverables'
			);
			Speaker_Application__c application = [
				SELECT Review_Count__c, Average_Score__c
				FROM Speaker_Application__c
				WHERE Event__c = :conference.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, application.Review_Count__c, 'Two reviews');
			Assert.areEqual(4.5, application.Average_Score__c, 'Their average');
			Assert.areEqual(
				6,
				[
					SELECT COUNT()
					FROM Event_Registration__c
					WHERE Event__c = :conference.Id AND Sample_Data__c = TRUE
					WITH SYSTEM_MODE
				],
				'Six conference registrations'
			);
			Assert.areEqual(
				4,
				[
					SELECT COUNT()
					FROM Event_Attendee__c
					WHERE Event_Registration__r.Event__c = :conference.Id AND Status__c = 'Attended'
					WITH SYSTEM_MODE
				],
				'Some attendees are checked in'
			);
			Assert.areEqual(
				4,
				[
					SELECT COUNT()
					FROM Event_Registration__c
					WHERE Event__r.Name = :COMMUNITY
					WITH SYSTEM_MODE
				],
				'Four community registrations'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSampleEventsAndLeavesRealOnes() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();
			Event__c real = new Event__c(
				Name = 'Real Event',
				Status__c = 'Draft',
				Format__c = 'In Person',
				Start__c = Datetime.now().addDays(20),
				End__c = Datetime.now().addDays(20).addHours(2)
			);
			insert as user real;
			Contact person = TestDataFactory.person(new Contact(LastName = 'Real Person'));
			insert as user person;
			insert as user new Event_Registration__c(
				Event__c = real.Id,
				Contact__c = person.Id,
				Status__c = 'Registered',
				Source__c = 'Staff'
			);

			Test.startTest();
			loadEverything();
			SampleDataFile.removeChunkSize = 3;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Event__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(1, [SELECT COUNT() FROM Event__c], 'The real event stays');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Event_Registration__c WITH SYSTEM_MODE],
				'The real registration stays'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Event_Attendee__c WITH SYSTEM_MODE],
				'The sample attendees went with their registrations'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Event_Track__c WITH SYSTEM_MODE],
				'The sample tracks went with their event'
			);
		}
	}

	@IsTest
	static void withoutSamplePeopleNobodyIsRegistered() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Event_Registration__c WITH SYSTEM_MODE],
				'No sample people, no registrations'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Event_Sponsor__c WITH SYSTEM_MODE],
				'No sample organizations, no sponsors'
			);
		}
	}
}
