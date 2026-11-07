@IsTest(testFor='ApexClass:DuplicateRulesStarter, ApexClass:OrgMetadataApi')
private class DuplicateRulesStarterTest {
	private static final List<String> RULE_ADMIN = new List<String>{
		'BarnCRM_Admin',
		'BarnCRM_Metadata_Admin'
	};
	private static final String OK_MATCH = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body><upsertMetadataResponse><result><created>true</created><fullName>Contact.BarnCRM_People_Match</fullName><success>true</success></result></upsertMetadataResponse></soapenv:Body></soapenv:Envelope>';
	private static final String REFUSED = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body><upsertMetadataResponse><result><errors><message>Field Phone is not valid</message><statusCode>FIELD_INTEGRITY_EXCEPTION</statusCode></errors><fullName>Contact.BarnCRM_People_Duplicates</fullName><success>false</success></result></upsertMetadataResponse></soapenv:Body></soapenv:Envelope>';
	private static final String FAULT = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><soapenv:Body><soapenv:Fault><faultcode>sf:INVALID_SESSION_ID</faultcode><faultstring>INVALID_SESSION_ID: Invalid Session ID</faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>';

	private static List<String> bodies = new List<String>();

	private class MetadataMock implements HttpCalloutMock {
		private final String body;

		MetadataMock(String body) {
			this.body = body;
		}

		public HttpResponse respond(HttpRequest request) {
			bodies.add(request.getBody());
			HttpResponse response = new HttpResponse();
			response.setStatusCode(body == FAULT ? 500 : 200);
			response.setBody(body);
			return response;
		}
	}

	@TestSetup
	static void createUsers() {
		TestUsers.withPermissionSets(RULE_ADMIN);
	}

	private static void connected() {
		ImportNewFieldService.systemPermissionOverride = true;
		ImportNewFieldService.connectedOverride = true;
		ImportNewFieldService.calloutStatusOverride = 'Enabled';
	}

	private static List<DuplicateRule> rules(String rows) {
		return (List<DuplicateRule>) JSON.deserialize(rows, List<DuplicateRule>.class);
	}

	@IsTest
	static void viewSaysWhatEachSetNeedsAndListsTheOrgsOwnRules() {
		System.runAs(TestUsers.withPermissionSets(RULE_ADMIN)) {
			connected();
			DuplicateRulesStarter.matchStatusOverride = new Map<String, String>{
				'BarnCRM_Household_Match' => 'Active'
			};
			DuplicateSelector.rulesOverride = rules(
				'[{"DeveloperName":"Standard_Contact_Duplicate_Rule","MasterLabel":"Standard Contact Duplicate Rule","SobjectType":"Contact","IsActive":true},' +
				'{"DeveloperName":"BarnCRM_Household_Duplicates","MasterLabel":"BarnCRM Household Duplicates","SobjectType":"Account","IsActive":false}]'
			);
			Test.startTest();
			DuplicateRulesStarter.StarterView view = DuplicateRulesStarter.getView();
			Test.stopTest();

			Assert.isTrue(view.connected, 'The connection is on.');
			Assert.areEqual(2, view.sets.size(), 'People and households.');
			DuplicateRulesStarter.SetView people = view.sets[0];
			Assert.areEqual(DuplicateRulesStarter.CREATE, people.action, 'Nothing exists yet.');
			Assert.areEqual(2, people.steps.size(), 'A matching rule and a duplicate rule.');
			Assert.areEqual(1, people.orgRules.size(), 'The standard rule is listed.');
			Assert.isTrue(
				people.orgRules[0].contains('Standard Contact Duplicate Rule'),
				'Named in words.'
			);
			DuplicateRulesStarter.SetView households = view.sets[1];
			Assert.areEqual(DuplicateRulesStarter.REPAIR, households.action, 'Rule turned off.');
			Assert.areEqual(1, households.steps.size(), 'Only the duplicate rule is rewritten.');
			Assert.isTrue(households.orgRules.isEmpty(), 'BarnCRM rule is not the org rule.');
		}
	}

	@IsTest
	static void activeSetNeedsNothingAndAnActivatingOneWaits() {
		System.runAs(TestUsers.withPermissionSets(RULE_ADMIN)) {
			connected();
			DuplicateRulesStarter.matchStatusOverride = new Map<String, String>{
				'BarnCRM_People_Match' => 'Active',
				'BarnCRM_Household_Match' => 'Activating'
			};
			DuplicateSelector.rulesOverride = rules(
				'[{"DeveloperName":"BarnCRM_People_Duplicates","MasterLabel":"BarnCRM People Duplicates","SobjectType":"Contact","IsActive":true}]'
			);
			Test.startTest();
			DuplicateRulesStarter.StarterView view = DuplicateRulesStarter.getView();
			Test.stopTest();
			Assert.areEqual(DuplicateRulesStarter.NONE, view.sets[0].action, 'All active.');
			Assert.areEqual(DuplicateRulesStarter.WAIT, view.sets[1].action, 'Activating.');
			try {
				DuplicateRulesStarter.start(new List<String>{ 'People', 'Household' });
				Assert.fail('Nothing to do.');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_DuplicateStarter_NothingToDo'),
					e.getMessage(),
					'Says so in words.'
				);
			}
		}
	}

	@IsTest
	static void startWithoutConnectionExplains() {
		System.runAs(TestUsers.withPermissionSets(RULE_ADMIN)) {
			ImportNewFieldService.systemPermissionOverride = true;
			ImportNewFieldService.connectedOverride = false;
			Test.startTest();
			try {
				DuplicateRulesStarter.start(new List<String>{ 'People' });
				Assert.fail('No connection.');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_DuplicateStarter_ConnectionNeeded'),
					e.getMessage(),
					'Explains the connection.'
				);
			}
			Test.stopTest();
		}
	}

	@IsTest
	static void viewNeedsTheSettingsPermission() {
		System.runAs(TestUsers.standardUser('NoSettings')) {
			try {
				DuplicateRulesStarter.getView();
				Assert.fail('Refused.');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_DuplicateStarter_NoPermission'),
					e.getMessage(),
					'Refused in words.'
				);
			}
		}
	}

	@IsTest
	static void startQueuesTheMatchingRulesFirst() {
		System.runAs(TestUsers.withPermissionSets(RULE_ADMIN)) {
			connected();
			DuplicateRulesStarter.matchStatusOverride = new Map<String, String>();
			DuplicateSelector.rulesOverride = new List<DuplicateRule>();
			Test.setMock(HttpCalloutMock.class, new MetadataMock(OK_MATCH));
			Test.startTest();
			DuplicateRulesStarter.start(new List<String>{ 'People' });
			Test.stopTest();
			Assert.areEqual(1, bodies.size(), 'One upsert call.');
			String sent = bodies[0];
			Assert.isTrue(sent.contains('xsi:type="met:MatchingRule"'), 'A matching rule.');
			Assert.isTrue(
				sent.contains('<met:fullName>Contact.BarnCRM_People_Match</met:fullName>'),
				'BarnCRM-named.'
			);
			Assert.isTrue(sent.contains('<met:ruleStatus>Active</met:ruleStatus>'), 'Activated.');
			Assert.isFalse(sent.contains('Household'), 'Only the chosen set.');
		}
	}

	@IsTest
	static void laterTryWritesTheDuplicateRuleOnceTheMatchIsActive() {
		System.runAs(TestUsers.withPermissionSets(RULE_ADMIN)) {
			DuplicateRulesStarter.matchStatusOverride = new Map<String, String>{
				'BarnCRM_People_Match' => 'Active',
				'BarnCRM_Household_Match' => 'Active'
			};
			DuplicateSelector.rulesOverride = rules(
				'[{"DeveloperName":"Standard_Account_Duplicate_Rule","MasterLabel":"Standard Account Duplicate Rule","SobjectType":"Account","IsActive":true}]'
			);
			Test.setMock(HttpCalloutMock.class, new MetadataMock(REFUSED));
			Test.startTest();
			new DuplicateRulesStarter.StarterJob(new List<String>{ 'People', 'Household' }, 1)
				.execute(null);
			Test.stopTest();
			Assert.areEqual(1, bodies.size(), 'Both rules in one call.');
			String sent = bodies[0];
			Assert.isTrue(sent.contains('xsi:type="met:DuplicateRule"'), 'Duplicate rules.');
			Assert.isTrue(
				sent.contains('<met:matchingRule>BarnCRM_Household_Match</met:matchingRule>'),
				'Uses BarnCRM matching rule.'
			);
			Assert.isTrue(sent.contains('<met:field>RecordType</met:field>'), 'Households only.');
			Assert.isTrue(
				sent.contains('<met:sortOrder>2</met:sortOrder>'),
				'After the org rule on Account.'
			);
			Assert.isTrue(
				sent.contains('<met:actionOnInsert>Allow</met:actionOnInsert>'),
				'Allows.'
			);
		}
	}

	@IsTest
	static void aRefusedSessionNeverThrowsFromTheJob() {
		System.runAs(TestUsers.withPermissionSets(RULE_ADMIN)) {
			DuplicateRulesStarter.matchStatusOverride = new Map<String, String>();
			Test.setMock(HttpCalloutMock.class, new MetadataMock(FAULT));
			Test.startTest();
			new DuplicateRulesStarter.StarterJob(new List<String>{ 'People' }, 0).execute(null);
			Test.stopTest();
			Assert.areEqual(1, bodies.size(), 'Tried once and stopped.');
		}
	}

	@IsTest
	static void resultsReadEachComponentAndAFaultThrows() {
		// runs-as: deploying user (pure parsing of a response text, no data, query or permission)
		List<OrgMetadataApi.Result> results = OrgMetadataApi.results(REFUSED);
		Assert.areEqual(1, results.size(), 'One result.');
		Assert.isFalse(results[0].success, 'Refused.');
		Assert.areEqual('Field Phone is not valid', results[0].message, 'The API words.');
		Assert.isTrue(OrgMetadataApi.results(OK_MATCH)[0].success, 'Saved.');
		try {
			OrgMetadataApi.results(FAULT);
			Assert.fail('A fault throws.');
		} catch (OrgMetadataApi.MetadataException e) {
			Assert.isTrue(e.getMessage().contains('INVALID_SESSION_ID'), 'Its words.');
		}
	}
}
