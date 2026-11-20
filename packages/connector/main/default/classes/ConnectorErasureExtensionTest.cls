/**
 * Erasing a person deletes the Connector runs that name them (CN-18; canonical model R-ER8,
 * R-CR17; design Section 5). Runs through Core's `PersonErasure`, which finds the extension by
 * name, as a person who may erase but has no Connector access: every run whose Input, State or
 * Step Log names the person's record Id or one of their email addresses (as a whole address,
 * ignoring capitals) is deleted and listed by Id; other runs and the recipe stay; the preview
 * deletes nothing; and a search too full to be sure refuses the whole erasure.
 */
@IsTest(testFor='ApexClass:ConnectorErasureExtension, ApexClass:ConnectorRunStore')
private class ConnectorErasureExtensionTest {
	private static final String MAIL = 'ana.lee@example.org';

	@TestSetup
	static void makeUsers() {
		TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Erase_People' });
	}

	/** May erase people; holds no BarnCRM Connector permission set. */
	private static User eraser() {
		return TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Erase_People' });
	}

	private static Contact ana() {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
		Contact person = HouseholdTestDataFactory.newContact('Ana', 'Lee');
		person.Email = MAIL;
		insert as user person;
		return person;
	}

	private static Connector_Recipe__c recipe() {
		return ConnectorRecipeTestData.recipe(
			'Sign Ups',
			ConnectorRecipeTestData.document('[{"id":"end","kind":"stop","outcome":"Succeeded"}]'),
			true,
			ConnectorRecipes.RUN_AS_AUTOMATION
		);
	}

	private static Connector_Run__c run(Id recipeId, String input, String state, String stepLog) {
		return new Connector_Run__c(
			Recipe__c = recipeId,
			Status__c = ConnectorRunStore.SUCCEEDED,
			Started_By__c = 'Webhook',
			Ran_As__c = ConnectorRecipes.RUN_AS_AUTOMATION,
			Recipe_Version__c = 1,
			Input_JSON__c = input,
			State_JSON__c = state,
			Step_Log_JSON__c = stepLog,
			Reference__c = ConnectorWebhooks.newReference(),
			Is_Test__c = false
		);
	}

	private static Set<Id> remaining() {
		return new Map<Id, Connector_Run__c>([SELECT Id FROM Connector_Run__c WITH SYSTEM_MODE]).keySet();
	}

	private static PersonErasure.Change runsChange(PersonErasure.Result result) {
		String label = Connector_Run__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural();
		for (PersonErasure.Change change : result.getChanges()) {
			if (change.getAction() == PersonErasure.DELETED && change.getObjectLabel() == label) {
				return change;
			}
		}
		return null;
	}

	@IsTest
	static void anErasureDeletesTheRunsThatNameThePersonAndKeepsTheRest() {
		System.runAs(eraser()) {
			Contact person = ana();
			Connector_Recipe__c recipe = recipe();
			List<Connector_Run__c> runs = new List<Connector_Run__c>{
				run(recipe.Id, '{"recordId":"' + person.Id + '"}', null, null),
				run(recipe.Id, '{"amount":5}', null, '[{"step":"look","message":"Found ANA.Lee@Example.org"}]'),
				run(
					recipe.Id,
					null,
					'{"steps":{"find":{"records":[{"Id":"' + String.valueOf(person.Id).left(15) + '"}]}}}',
					null
				),
				run(recipe.Id, '{"email":"joana.lee@example.org"}', null, null),
				run(recipe.Id, '{"email":"ana.lee@example.org.uk"}', null, null),
				run(recipe.Id, '{"email":"someone@example.org"}', null, null)
			};
			insert as system runs;
			Test.setFixedSearchResults(new List<Id>{ runs[3].Id, runs[5].Id });

			Test.startTest();
			PersonErasure.Result result = PersonErasure.erase(person.Id, 'Ana Lee', null);
			Test.stopTest();

			Set<Id> kept = remaining();
			Assert.areEqual(new Set<Id>{ runs[3].Id, runs[4].Id, runs[5].Id }, kept, 'Only runs naming Ana go.');
			Assert.isNotNull(runsChange(result), 'Listed as Deleted Connector Runs.');
			String details = [SELECT Details__c FROM Erasure__c WITH SYSTEM_MODE LIMIT 1].Details__c;
			for (Integer i = 0; i < 3; i++) {
				Assert.isTrue(details.contains(runs[i].Id), 'The Erasure record lists each run by Id.');
			}
			Assert.isFalse(details.contains(MAIL), 'And never an erased value.');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Connector_Recipe__c WITH SYSTEM_MODE],
				'The recipe, the admin\'s setting, stays.'
			);
		}
	}

	@IsTest
	static void thePreviewListsTheRunsWithoutDeletingThem() {
		System.runAs(eraser()) {
			Contact person = ana();
			Connector_Recipe__c recipe = recipe();
			insert as system run(recipe.Id, '{"email":"' + MAIL + '"}', null, null);

			Test.startTest();
			PersonErasure.Result result = PersonErasure.preview(person.Id);
			Test.stopTest();

			Assert.isNotNull(runsChange(result), 'The preview lists the run.');
			Assert.areEqual(1, remaining().size(), 'And deletes nothing.');
		}
	}

	@IsTest
	static void aSearchTooFullToBeSureRefusesTheErasure() {
		System.runAs(eraser()) {
			Contact person = ana();
			Connector_Recipe__c recipe = recipe();
			List<Connector_Run__c> runs = new List<Connector_Run__c>();
			for (Integer i = 0; i < ConnectorRunStore.MOST_SEARCHED; i++) {
				runs.add(run(recipe.Id, '{"n":' + i + '}', null, null));
			}
			insert as system runs;
			Test.setFixedSearchResults(new List<Id>(new Map<Id, Connector_Run__c>(runs).keySet()));
			ConnectorErasureExtension extension = new ConnectorErasureExtension();

			Test.startTest();
			extension.beforeErase(person.Id);
			String refused;
			try {
				extension.erase(person.Id);
			} catch (PersonErasure.ErasureException tooMany) {
				refused = tooMany.getMessage();
			}
			extension.afterErase(person.Id);
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text(
					'Connector',
					'Connector_Erase_TooManyRuns',
					new List<Object>{ ConnectorRunStore.MOST_SEARCHED }
				),
				refused
			);
			Assert.areEqual(ConnectorRunStore.MOST_SEARCHED, remaining().size(), 'Nothing is deleted.');
			Assert.isTrue(extension.fieldsToKeep(Contact.SObjectType).isEmpty());
		}
	}

	@IsTest
	static void anAddressIsFoundWholeAndTheIdKeepsItsCapitals() {
		System.runAs(eraser()) {
			String id15 = '003000000000AbC';
			List<String> mails = new List<String>{ MAIL };

			Test.startTest();
			Boolean quoted = ConnectorRunStore.names('{"to":"' + MAIL + '"}', id15, mails);
			Boolean inText = ConnectorRunStore.names('Write to Ana.Lee@example.org. Thanks', id15, mails);
			Boolean longer = ConnectorRunStore.names('joana.lee@example.org', id15, mails);
			Boolean subdomain = ConnectorRunStore.names('ana.lee@example.org.uk', id15, mails);
			Boolean byId = ConnectorRunStore.names('{"Id":"003000000000AbCAAA"}', id15, mails);
			Boolean otherCase = ConnectorRunStore.names('{"Id":"003000000000ABC"}', id15, mails);
			Test.stopTest();

			Assert.isTrue(quoted);
			Assert.isTrue(inText, 'Capitals and a full stop after it do not matter.');
			Assert.isFalse(longer, 'Another address that ends the same way is not hers.');
			Assert.isFalse(subdomain);
			Assert.isTrue(byId, 'The 18 character Id starts with the 15.');
			Assert.isFalse(otherCase, 'A 15 character Id differing in capitals is another record.');
			Assert.isFalse(ConnectorRunStore.names(null, id15, mails));
		}
	}
}
