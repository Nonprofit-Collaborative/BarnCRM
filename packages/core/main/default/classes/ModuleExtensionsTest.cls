/**
 * Module wiring read from the catalog (D-200 S1): a seam's classes are found per module in
 * catalog order, a class that is not installed or does not implement the seam is skipped, and
 * a test's stand-ins take a module's place. Each module's own tests check that its row resolves.
 */
// runs-as: deploying user (pure logic: resolves classes by name from in-memory catalog rows, no DML or SOQL)
@IsTest(testFor='ApexClass:ModuleExtensions')
private class ModuleExtensionsTest {
	private class FakeProvider implements NightlyStepProvider {
		public List<NightlyStep> nightlySteps() {
			return new List<NightlyStep>();
		}
	}

	@IsTest
	static void aMissingOrWrongClassIsSkipped() {
		ModuleExtensions.catalogOverride = new List<BarnCRM_Module__mdt>{
			new BarnCRM_Module__mdt(
				DeveloperName = 'Example',
				Extensions__c = 'HealthCheckExtension: Other\nNightlyStepProvider: Example_Missing, ModuleAccessSyncs'
			)
		};

		Test.startTest();
		List<Object> found = ModuleExtensions.all(NightlyStepProvider.class);
		Test.stopTest();

		Assert.isTrue(found.isEmpty(), 'Neither class can stand in for the seam: ' + found);
		Assert.isNull(ModuleExtensions.first(NightlyStepProvider.class), 'None first either');
	}

	@IsTest
	static void standInsFollowTheCatalogAndCanHideTheRest() {
		ModuleExtensions.catalogOverride = new List<BarnCRM_Module__mdt>{
			new BarnCRM_Module__mdt(DeveloperName = 'Example_A'),
			new BarnCRM_Module__mdt(DeveloperName = 'Example_B')
		};
		FakeProvider a = new FakeProvider();
		FakeProvider b = new FakeProvider();
		ModuleExtensions.stubForTest(NightlyStepProvider.class, 'Example_B', b, false);
		ModuleExtensions.stubForTest(NightlyStepProvider.class, 'Example_A', a, true);

		Map<String, Object> byModule = ModuleExtensions.byModule(NightlyStepProvider.class);

		Assert.areEqual(2, byModule.size(), 'Both stand-ins');
		Assert.areEqual(a, ModuleExtensions.forModule(NightlyStepProvider.class, 'example_a'));
		Assert.isNull(ModuleExtensions.forModule(NightlyStepProvider.class, 'Example_C'));
	}
}
