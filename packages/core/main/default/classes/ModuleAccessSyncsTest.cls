/**
 * Core's access sync for every module, read from the catalog (ADR-0131, D-200 S1): the hourly
 * check asks every module with sets, Turn on only that module, a pass runs the module's own
 * step, a failing step never stops it, nothing runs while the module is off, and the install
 * gives the installer the admin sets. No module is needed: the catalog is supplied in memory.
 */
@IsTest(testFor='ApexClass:ModuleAccessSyncs, ApexClass:ModuleExtensions')
private class ModuleAccessSyncsTest {
	@TestSetup
	static void createAdmin() {
		TestUsers.admin();
	}

	private class StepFailedException extends Exception {
	}

	/** A module step that counts its runs, and can fail. */
	private class CountingStep implements ModuleAccessStep {
		public Integer runs = 0;
		public Boolean fails = false;

		public void afterSync() {
			runs++;
			if (fails) {
				throw new StepFailedException('Step failed');
			}
		}
	}

	/** Two example modules whose sets are not installed, and one with no sets. */
	private static void catalogOf() {
		ModuleExtensions.catalogOverride = new List<BarnCRM_Module__mdt>{
			new BarnCRM_Module__mdt(
				DeveloperName = 'Example_A',
				Access_By_Permission_Set__c = 'Example_A_Admin=BarnCRM_Admin',
				Access_By_Role__c = 'Example_A_Staff=Program_Staff,Fundraising_Staff'
			),
			new BarnCRM_Module__mdt(
				DeveloperName = 'Example_B',
				Access_By_Role__c = 'Example_B_Staff=Program_Staff'
			),
			new BarnCRM_Module__mdt(DeveloperName = 'Example_None')
		};
	}

	private static Integer loggedFor(String context) {
		return [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :context WITH SYSTEM_MODE];
	}

	@IsTest
	static void theHourlyCheckAsksEveryModuleWithSets() {
		System.runAs(TestUsers.admin()) {
			catalogOf();

			Test.startTest();
			new TabAccessScheduler().execute(null);
			Test.stopTest();

			Assert.areEqual(
				new List<String>{ 'Example_A', 'Example_B' },
				ModuleAccessSyncs.requested,
				'Every module that names sets, in catalog order, and no other'
			);
		}
	}

	@IsTest
	static void turningOnAsksOnlyThatModule() {
		System.runAs(TestUsers.admin()) {
			catalogOf();

			Test.startTest();
			ModuleAccessSyncs.requestFor('example_b');
			ModuleAccessSyncs.requestFor('Example_None');
			ModuleAccessSyncs.requestFor('Example_Absent');
			Test.stopTest();

			Assert.areEqual(
				new List<String>{ 'Example_B' },
				ModuleAccessSyncs.requested,
				'Only the module turned on, and only when it names sets'
			);
		}
	}

	@IsTest
	static void aPassRunsTheModuleStepAndAFailureIsLogged() {
		System.runAs(TestUsers.admin()) {
			catalogOf();
			CountingStep step = new CountingStep();
			step.fails = true;
			ModuleExtensions.stubForTest(ModuleAccessStep.class, 'Example_A', step, true);

			Test.startTest();
			Boolean more = ModuleAccessSyncs.syncOnce('Example_A');
			Test.stopTest();

			Assert.isFalse(more, 'Sets that are not installed leave nothing to give');
			Assert.areEqual(1, step.runs, 'The module step ran once after the pass');
			Assert.areEqual(1, loggedFor('Example_AAccessSync'), 'Its failure is logged');
		}
	}

	@IsTest
	static void givesNothingWhileTheModuleIsOff() {
		System.runAs(TestUsers.admin()) {
			catalogOf();
			CountingStep step = new CountingStep();
			ModuleExtensions.stubForTest(ModuleAccessStep.class, 'Example_A', step, true);
			BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
			settings.Modules_Turned_Off__c = 'Example_A';
			Database.upsert(settings, AccessLevel.SYSTEM_MODE);

			Test.startTest();
			Boolean more = ModuleAccessSyncs.syncOnce('Example_A');
			Test.stopTest();

			Assert.isFalse(more, 'Nothing to do');
			Assert.areEqual(0, step.runs, 'Not even the module step');
		}
	}

	@IsTest
	static void theAdminSetsAreThoseGivenToBarnCrmAdminHolders() {
		// runs-as: deploying user (pure logic over in-memory catalog rows, no DML or SOQL)
		catalogOf();
		Assert.areEqual(
			new List<String>{ 'Example_A_Admin' },
			ModuleAccessSyncs.adminSets('Example_A'),
			'The installer gets what BarnCRM Admin holders get'
		);
		Assert.isTrue(ModuleAccessSyncs.adminSets('Example_B').isEmpty(), 'Roles only: none');
	}

	@IsTest
	static void theInstallQueuesTheInstallerGrantAndTheSync() {
		System.runAs(TestUsers.admin()) {
			catalogOf();
			CountingStep step = new CountingStep();
			ModuleExtensions.stubForTest(ModuleAccessStep.class, 'Example_A', step, true);

			Test.startTest();
			ModuleAccessSyncs.setUp('Example_A', UserInfo.getUserId());
			Test.stopTest();

			Assert.areEqual(new List<String>{ 'Example_A' }, ModuleAccessSyncs.requested, 'Queued');
			Assert.areEqual(1, step.runs, 'The queued job ran the sync after the grant');
		}
	}

	@IsTest
	static void theWrittenMapsAreRead() {
		// runs-as: deploying user (pure parsing of a text value, no data access)
		Map<String, List<String>> bySet = ModuleExtensions.parseMap(
			' A_Admin = BarnCRM_Admin ; A_Staff=Program_Staff, Fundraising_Staff;;=Lost'
		);
		Assert.areEqual(new List<String>{ 'A_Admin', 'A_Staff' }, new List<String>(bySet.keySet()));
		Assert.areEqual(
			new List<String>{ 'Program_Staff', 'Fundraising_Staff' },
			bySet.get('A_Staff'),
			'Holders trimmed, in written order'
		);
		Assert.isTrue(ModuleExtensions.parseMap(null).isEmpty(), 'Empty means none');
	}
}
