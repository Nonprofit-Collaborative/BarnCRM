/**
 * The Rollup Builder's part of Where Used (C-59): a rollup is found by its counted object's
 * filter, its relationship path, its result field and, for a whole object, by what it counts and
 * where it writes; Core's Where Used finds this extension by name.
 *
 * People are counted on their organization (`AccountId`), so the test needs no giving object.
 */
@IsTest(testFor='ApexClass:RollupsWhereUsedExtension')
private class RollupsWhereUsedExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Rollup_Builder_Admin');
	}

	private static Rollup_Definition__c staffWithEmail() {
		return new Rollup_Definition__c(
			Name = 'Staff with email',
			Definition_Key__c = 'Test_Where_Used_Staff',
			Source_Object__c = 'Contact',
			Relationship_Path__c = 'AccountId',
			Aggregate__c = 'COUNT',
			Filter_JSON__c = '{"version":1,"conditions":[{"id":1,"field":"Email","operator":"is not null"}]}',
			Target_Object__c = 'Account',
			Target_Field__c = 'NumberOfEmployees',
			Mode__c = RollupService.MODE_BOTH,
			Fiscal_Year_Aware__c = false,
			Active__c = false
		);
	}

	private static List<String> partsFor(String objectName, String fieldName) {
		for (
			WhereUsedService.Reference reference : new RollupsWhereUsedExtension()
				.references(WhereUsedService.target(objectName, fieldName))
		) {
			if (reference.getName() == 'Staff with email') {
				Assert.areEqual(NamespaceUtil.qualify('Rollup_Builder'), reference.getEditTab());
				Assert.areEqual(
					BarnHelp.text('Rollups', 'Core_RollupBuilder_WhereUsedBreaks'),
					reference.getBreaks()
				);
				return reference.getParts();
			}
		}
		return new List<String>();
	}

	@IsTest
	static void aRollupIsFoundByEveryPartThatNamesTheTarget() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			insert as system staffWithEmail();

			Test.startTest();
			List<String> filter = partsFor('Contact', 'Email');
			List<String> path = partsFor('Contact', 'AccountId');
			List<String> result = partsFor('Account', 'NumberOfEmployees');
			List<String> counted = partsFor('Contact', null);
			List<String> written = partsFor('Account', null);
			List<String> none = partsFor('Contact', 'Department');
			Test.stopTest();

			Assert.areEqual(
				new List<String>{ System.Label.Core_RollupBuilder_WhereUsedSourceFilter },
				filter
			);
			Assert.areEqual(
				new List<String>{ System.Label.Core_RollupBuilder_WhereUsedPath },
				path
			);
			Assert.areEqual(
				new List<String>{ System.Label.Core_RollupBuilder_WhereUsedTargetField },
				result
			);
			Assert.areEqual(
				new List<String>{ System.Label.Core_RollupBuilder_WhereUsedCounts },
				counted
			);
			Assert.isTrue(
				written.contains(System.Label.Core_RollupBuilder_WhereUsedWrites),
				String.valueOf(written)
			);
			Assert.isTrue(none.isEmpty(), 'A field the rollup does not name finds nothing.');
		}
	}

	@IsTest
	static void aHouseholdTokenEndsThePath() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			WhereUsedService.Target target = WhereUsedService.target('Contact', 'AccountId');

			Assert.isTrue(
				RollupsWhereUsedExtension.pathNames(target, 'Contact', 'ReportsToId | AccountId')
			);
			Assert.isFalse(RollupsWhereUsedExtension.pathNames(target, 'Contact', '{Household}'));
			Assert.isFalse(RollupsWhereUsedExtension.pathNames(target, 'Contact', ''));
		}
	}

	@IsTest
	static void coreFindsThisExtensionByName() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			Assert.isInstanceOfType(
				WhereUsedExtensions.findAll().get('RollupsWhereUsedExtension'),
				RollupsWhereUsedExtension.class
			);
		}
	}
}
