/**
 * The Forms sample data set (release 1.25): a volunteer sign-up and an event registration form,
 * both published, a contact form left as a draft, and five submissions in different states. It
 * is counted on the card, removed again with real forms left alone, and loaded without Core's
 * sample people (the submissions then name no person). Run as a BarnCRM admin holding Forms
 * Admin, the person who loads sample data.
 *
 * The set ships as FormsSampleData.json and Core's SampleDataFile loads it (D-200 S2). The
 * stages are called directly, as the other modules' tests do, because a test runs only the
 * first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class FormsSampleDataTest {
	private static final String FILE = 'FormsSampleData';

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith('Forms_Admin');
	}

	private static User admin() {
		return TestUsers.adminWith('Forms_Admin');
	}

	/** Two of Core's sample people and one of its sample organizations. */
	private static void samplePeopleAndOrganizations() {
		List<Contact> people = new List<Contact>();
		for (String key : new List<String>{ 'H001-1', 'H003-1' }) {
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
		Account organization = (Account) TestDataFactory.pastDuplicateRules(
			AccountKindsTestData.organization('Sample Org O001')
		);
		organization.Sample_Data__c = true;
		organization.Sample_Data_Key__c = 'O001';
		insert organization;
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
	static void theLoadBuildsThreeFormsTheirVersionsAndSubmissions() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();

			Test.startTest();
			loadEverything();
			Test.stopTest();

			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Forms', module.moduleName(), 'The name startAfter looks for');
			Assert.areEqual(3, module.countLoaded(), 'Three sample forms are counted');
			Assert.isTrue(module.hasSampleRecords(), 'The card sees them');

			Map<String, Form__c> forms = new Map<String, Form__c>();
			for (Form__c form : [
				SELECT Name, Status__c, Public__c, Published_Version__c, Definition__c
				FROM Form__c
				WHERE Sample_Data__c = TRUE
				WITH SYSTEM_MODE
			]) {
				forms.put(form.Name, form);
				Map<String, Object> definition = FormRules.parse(form.Definition__c);
				Assert.isFalse(FormRules.steps(definition).isEmpty(), form.Name + ' has steps');
				Assert.isFalse(
					FormRules.records(definition).isEmpty(),
					form.Name + ' writes a record'
				);
				Assert.isFalse(form.Public__c, form.Name + ' is not open to the public');
			}
			Assert.areEqual('Published', forms.get('Volunteer Sign-Up').Status__c);
			Assert.areEqual('Published', forms.get('Event Registration').Status__c);
			Assert.areEqual('Draft', forms.get('Contact Us').Status__c, 'One form is a draft');
			Assert.areEqual(1, forms.get('Volunteer Sign-Up').Published_Version__c);

			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Form_Version__c
					WHERE Form__r.Sample_Data__c = TRUE
					WITH SYSTEM_MODE
				],
				'The published forms have a version, the draft has none'
			);
			for (Form_Version__c version : [
				SELECT Definition__c, Form__r.Definition__c
				FROM Form_Version__c
				WITH SYSTEM_MODE
			]) {
				Assert.areEqual(
					version.Form__r.Definition__c,
					version.Definition__c,
					'A version holds the definition as published'
				);
			}
			Assert.areEqual(
				5,
				[SELECT COUNT() FROM Form_Submission__c WITH SYSTEM_MODE],
				'Five submissions'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Form_Submission__c
					WHERE Status__c = 'NeedsReview'
					WITH SYSTEM_MODE
				],
				'One waits for review'
			);
			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Form_Submission__c
					WHERE Status__c = 'Processed' AND Person__r.Sample_Data_Key__c != NULL
					WITH SYSTEM_MODE
				],
				'The processed submissions name a sample person'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Form_Submission__c
					WHERE Organization__r.Sample_Data_Key__c = 'O001'
					WITH SYSTEM_MODE
				],
				'The volunteer sign-up names a sample organization'
			);
		}
	}

	@IsTest
	static void theRemovalTakesTheSampleFormsAndLeavesRealOnes() {
		System.runAs(admin()) {
			samplePeopleAndOrganizations();
			Form__c real = new Form__c(Name = 'Real Form', Status__c = 'Draft');
			insert as user real;
			insert as user new Form_Submission__c(
				Form__c = real.Id,
				Status__c = 'Received',
				Source__c = 'Staff',
				Answers__c = '{}'
			);

			Test.startTest();
			loadEverything();
			SampleDataFile.removeChunkSize = 2;
			removeEverything();
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Form__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(1, [SELECT COUNT() FROM Form__c], 'The real form stays');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Form_Submission__c WITH SYSTEM_MODE],
				'The real submission stays; the sample ones went with their forms'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Form_Version__c WITH SYSTEM_MODE],
				'The sample versions went with their forms'
			);
		}
	}

	@IsTest
	static void withoutSamplePeopleTheSubmissionsNameNoOne() {
		System.runAs(admin()) {
			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(3, [SELECT COUNT() FROM Form__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Form_Submission__c WHERE Person__c != NULL WITH SYSTEM_MODE],
				'No sample people, no linked person'
			);
		}
	}
}
