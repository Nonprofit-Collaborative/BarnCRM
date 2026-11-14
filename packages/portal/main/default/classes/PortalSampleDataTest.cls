/**
 * The Portal Builder sample data set (release 1.25): one portal, left Inactive so nothing is open
 * to anyone, with Core's My Account template and an access for three sample people. It is
 * counted on the card, removed again with real portals left alone, and loaded without Core's
 * sample people (the portal then has no accesses). Run as a BarnCRM admin holding Portal Admin,
 * the person who loads sample data.
 *
 * The set ships as PortalSampleData.json and Core's SampleDataFile loads it (D-200 S2). The
 * stages are called directly, as the other modules' tests do, because a test runs only the
 * first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class PortalSampleDataTest {
	private static final String FILE = 'PortalSampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith('Portal_Admin');
	}

	private static User admin() {
		return TestUsers.adminWith('Portal_Admin');
	}

	/** Three of Core's sample people. */
	private static void samplePeople() {
		List<Contact> people = new List<Contact>();
		for (String key : new List<String>{ 'H001-1', 'H002-1', 'H003-1' }) {
			people.add(
				TestDataFactory.person(
					new Contact(
						FirstName = 'Sample',
						LastName = 'Person' + key.replace('-', ''),
						Email = 'sample' + key.replace('-', '') + '@example.org',
						Sample_Data__c = true,
						Sample_Data_Key__c = key
					)
				)
			);
		}
		insert people;
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
	static void theLoadBuildsAnInactivePortalWithItsAccesses() {
		System.runAs(admin()) {
			samplePeople();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Portal', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(1, module.countLoaded(), 'One sample portal is counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees it');

			Portal__c portal = [
				SELECT Status__c, Access_Mode__c, Second_Factor__c, Template__c
				FROM Portal__c
				WHERE Sample_Data__c = TRUE
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Inactive', portal.Status__c, 'Nothing is open to anyone');
			Assert.areEqual('Invited', portal.Access_Mode__c);
			Map<String, Object> template = (Map<String, Object>) JSON.deserializeUntyped(
				portal.Template__c
			);
			Assert.areEqual(
				2,
				((List<Object>) template.get('pages')).size(),
				'The My Account template has two pages'
			);
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Portal_Access__c
					WHERE Portal__r.Sample_Data__c = TRUE
					WITH SYSTEM_MODE
				],
				'Three people are invited'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Portal_Access__c
					WHERE Status__c = 'Suspended'
					WITH SYSTEM_MODE
				],
				'One access is suspended'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Portal_Session__c WITH SYSTEM_MODE],
				'Nobody has signed in'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSamplePortalAndLeavesRealOnes() {
		System.runAs(admin()) {
			samplePeople();
			Portal__c real = new Portal__c(
				Name = 'Real Portal',
				Key__c = 'real-portal',
				Status__c = 'Inactive',
				Access_Mode__c = 'Invited',
				Second_Factor__c = 'Off'
			);
			insert as user real;
			Contact person = TestDataFactory.person(new Contact(LastName = 'Real Person'));
			insert as user person;
			insert as user new Portal_Access__c(
				Portal__c = real.Id,
				Person__c = person.Id,
				Status__c = 'Active'
			);

			Test.startTest();
			loadEverything();
			SampleDataFile.removeChunkSize = 1;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Portal__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Portal__c WITH SYSTEM_MODE],
				'The real portal stays'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Portal_Access__c WITH SYSTEM_MODE],
				'The real access stays; the sample ones went with their portal'
			);
		}
	}

	@IsTest
	static void withoutSamplePeopleThePortalHasNoAccesses() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Portal__c WHERE Sample_Data__c = TRUE WITH SYSTEM_MODE]
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Portal_Access__c WITH SYSTEM_MODE],
				'No sample people, nobody invited'
			);
		}
	}
}
