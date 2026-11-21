/**
 * Dana opens Health Check and sees which connections still need their Setup step or their
 * principal access, which keys were replaced this week, and whether someone added more than
 * connection access to the "BarnCRM Connections" permission set (CN-01; review F11, F12).
 */
@IsTest(testFor='ApexClass:ConnectorHealthCheckExtension')
private class ConnectorHealthCheckExtensionTest {
	private class FakeOrg extends ConnectorOrg {
		Map<String, ConnectorOrg.Pair> pairs = new Map<String, ConnectorOrg.Pair>();
		Set<Id> granted = new Set<Id>();

		FakeOrg() {
			fake = true;
		}

		void add(String name, Boolean calloutsOn, Boolean accessOn) {
			ConnectorOrg.Pair pair = new ConnectorOrg.Pair();
			pair.name = name;
			pair.label = 'Label ' + name;
			pair.principal = ConnectorConnections.BEARER;
			pair.url = 'https://api.example.com';
			pair.linked = true;
			pair.calloutsEnabled = calloutsOn;
			pair.keyStored = true;
			pairs.put(name, pair);
			Id principal = Id.valueOf('001' + String.valueOf(pairs.size()).leftPad(12, '0'));
			pair.principalId = principal;
			if (accessOn) {
				granted.add(principal);
			}
		}

		public override Map<String, String> labelsByName() {
			Map<String, String> labels = new Map<String, String>();
			for (ConnectorOrg.Pair pair : pairs.values()) {
				labels.put(pair.name, pair.label);
			}
			return labels;
		}

		public override ConnectorOrg.Pair read(String name, String label) {
			return pairs.get(name);
		}

		public override Set<Id> grantedEntities(Id permissionSetId) {
			return granted.clone();
		}
	}

	@TestSetup
	static void createTestUser() {
		System.runAs(TestUsers.admin()) {
			dana();
		}
	}

	/** The Connector admin, created once by the setup method and found again by each test. */
	private static User dana() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static Set<String> keys(List<HealthCheckService.Finding> findings) {
		Set<String> found = new Set<String>();
		for (HealthCheckService.Finding finding : findings) {
			found.add(finding.getKey());
		}
		return found;
	}

	@IsTest
	static void connectionsNeedingAStepAndReplacedKeysAreListed() {
		System.runAs(dana()) {
			FakeOrg fake = new FakeOrg();
			fake.add('BarnConn_rest_aaaaaa', false, true);
			fake.add('BarnConn_rest_bbbbbb', true, false);
			ConnectorConnections.org = fake;
			insert as system new PermissionSet(Name = ConnectorConnections.ACCESS_SET, Label = 'BarnCRM Connections');
			insert as system new Merge_Journal__c(
				Kind__c = 'Connection',
				Status__c = 'Key Replaced',
				Message__c = 'Mail (x)'
			);

			Set<String> found = keys(new ConnectorHealthCheckExtension().findings());

			Assert.isTrue(found.contains('connector_callouts_off'), 'Callouts still off in Setup');
			Assert.isTrue(found.contains('connector_access_missing'), 'Principal access missing');
			Assert.isTrue(found.contains('connector_keys_replaced'), 'A key replaced this week (F11)');
			Assert.isFalse(found.contains('connector_access_set_extra'), 'The set holds connection access only');
		}
	}

	@IsTest
	static void anythingElseInTheConnectionsSetIsAWarning() {
		System.runAs(dana()) {
			FakeOrg fake = new FakeOrg();
			fake.add('BarnConn_rest_aaaaaa', true, true);
			fake.granted.add(UserInfo.getUserId());
			ConnectorConnections.org = fake;
			insert as system new PermissionSet(Name = ConnectorConnections.ACCESS_SET, Label = 'BarnCRM Connections');

			Set<String> found = keys(new ConnectorHealthCheckExtension().findings());

			Assert.isTrue(found.contains('connector_access_set_extra'), 'Another entity in the set (F12)');
			Assert.isFalse(found.contains('connector_callouts_off'), 'Nothing else to report');
		}
	}

	@IsTest
	static void nothingIsReportedWithoutConnections() {
		System.runAs(dana()) {
			ConnectorConnections.org = new FakeOrg();

			Assert.isTrue(new ConnectorHealthCheckExtension().findings().isEmpty(), 'A quiet report');
		}
	}

	@IsTest
	static void anActiveAutomationRecipeWithoutRecipeAccessIsAWarning() {
		System.runAs(dana()) {
			ConnectorConnections.org = new FakeOrg();
			ConnectorIdentity.automatedProcessOverride = '005000000000000';
			ConnectorRecipeTestData.recipe(
				'Unready',
				ConnectorRecipeTestData.document('[{"id":"end","kind":"stop","outcome":"Succeeded"}]'),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);

			Set<String> found = keys(new ConnectorHealthCheckExtension().findings());

			Assert.isTrue(found.contains('connector_recipe_access_unsaved'));
			Assert.isFalse(found.contains('connector_system_recipes'), 'No recipe runs as System.');
		}
	}
}
