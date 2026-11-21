/**
 * Where Used lists the recipes that name a field or object in a Find step, and the Mapper warns
 * before a map that a recipe links is changed (CN-06; design Section 2.3; ADR-0159).
 */
@IsTest(testFor='ApexClass:ConnectorWhereUsedExtension')
private class ConnectorWhereUsedExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	@IsTest
	static void findStepsAndLinkedMapsAreFound() {
		System.runAs(TestUsers.adminWith(ConnectorConnections.ADMIN_SET)) {
			Id mapId = ConnectorRecipeTestData.contactMap('Used Map');
			Id otherMap = ConnectorRecipeTestData.bodyMap('Unused Map');
			ConnectorRecipeTestData.recipe(
				'Uses Email',
				ConnectorRecipeTestData.document(
					'[{"id":"look","kind":"find","query":{"version":1,"object":"Contact","fields":["LastName"],' +
						'"filter":{"version":1,"conditions":[{"id":1,"field":"Email","operator":"is not null"}]}}},' +
						'{"id":"make","kind":"create","map":"' +
						mapId +
						'"}]'
				),
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorRecipeTestData.recipe(
				'Watches Titles',
				'{"version":1,"trigger":{"kind":"record","on":"changed","mode":"each","query":{"version":1,' +
					'"object":"Contact","fields":["LastName"],"filter":{"version":1,"conditions":' +
					'[{"id":1,"field":"Title","operator":"is not null"}]}}},"steps":[]}',
				true,
				ConnectorRecipes.RUN_AS_AUTOMATION
			);
			ConnectorWhereUsedExtension extension = new ConnectorWhereUsedExtension();

			Test.startTest();
			List<WhereUsedService.Reference> title = extension.references(WhereUsedService.target('Contact', 'Title'));
			List<WhereUsedService.Reference> email = extension.references(WhereUsedService.target('Contact', 'Email'));
			List<WhereUsedService.Reference> phone = extension.references(WhereUsedService.target('Contact', 'Phone'));
			List<WhereUsedService.Reference> contact = extension.references(WhereUsedService.target('Contact', null));
			List<WhereUsedService.Reference> mapUsers = WhereUsedService.mapUsers(mapId, 'Used Map');
			List<WhereUsedService.Reference> unused = WhereUsedService.mapUsers(otherMap, 'Unused Map');
			Test.stopTest();

			Assert.areEqual(1, email.size());
			Assert.areEqual('Uses Email', email[0].getName());
			Assert.areEqual(
				new List<String>{ BarnHelp.text('Connector', 'Connector_WhereUsed_Step', new List<Object>{ 'look' }) },
				email[0].getParts()
			);
			Assert.isTrue(email[0].getEditTab().endsWith('Super_Connector'));
			Assert.isTrue(phone.isEmpty());
			Assert.areEqual(1, title.size(), 'A Record Change trigger that filters on the field is listed.');
			Assert.areEqual('Watches Titles', title[0].getName());
			Assert.areEqual(
				new List<String>{ BarnHelp.text('Connector', 'Connector_WhereUsed_Trigger') },
				title[0].getParts()
			);
			Assert.areEqual(2, contact.size(), 'The Find step and the trigger both name Contact.');
			Assert.areEqual(1, mapUsers.size(), 'The Mapper warns before a linked map changes.');
			Assert.areEqual(
				new List<String>{ BarnHelp.text('Connector', 'Connector_WhereUsed_Step', new List<Object>{ 'make' }) },
				mapUsers[0].getParts()
			);
			Assert.isTrue(unused.isEmpty());
			Assert.isInstanceOfType(
				WhereUsedExtensions.findAll().get('ConnectorWhereUsedExtension'),
				ConnectorWhereUsedExtension.class
			);
		}
	}
}
