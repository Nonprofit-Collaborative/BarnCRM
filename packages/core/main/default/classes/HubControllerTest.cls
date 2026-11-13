/**
 * Maria lands on the Hub home page and is told what to do next. David, without the
 * Manage BarnCRM Settings permission, sees the same page and cannot change anything.
 * Finishing a step belongs to the Setup Assistant's own controller.
 */
@IsTest(testFor='ApexClass:HubController')
private class HubControllerTest {
	@TestSetup
	static void grantPermission() {
		System.runAs(TestUsers.admin()) {
			SettingsTestPermissions.grantTo('C03_Hub_Home_Test', UserInfo.getUserId());
		}
	}

	private static User buildDavid() {
		return SettingsTestPermissions.buildStandardUser('David', 'Okonkwo', 'davidh');
	}

	/**
	 * New household: a staff member whose access comes only from BarnCRM Staff is offered the
	 * button and gets an empty household, named with the placeholder, of the Household record
	 * type, created in system mode (ADR-0141).
	 */
	@IsTest
	static void newHouseholdCreatesAnEmptyHouseholdForStaff() {
		System.runAs(TestUsers.admin()) {
			User staff = TestUsers.minimumAccessUserWith(
				'Hubstaff',
				new List<String>{ 'BarnCRM_Staff' }
			);
			Boolean offered;
			Id householdId;

			Test.startTest();
			System.runAs(staff) {
				offered = HubController.getHomeModel().canCreateHousehold;
				householdId = HubController.createHousehold();
			}
			Test.stopTest();

			Assert.isTrue(offered, 'The button is offered');
			Account household = [
				SELECT Name, RecordTypeId, Member_Count__c
				FROM Account
				WHERE Id = :householdId
				WITH SYSTEM_MODE
			];
			Assert.areEqual(
				HouseholdService.householdRecordTypeId(),
				household.RecordTypeId,
				'A household'
			);
			Assert.areEqual(Label.Core_Households_NamePlaceholder, household.Name, 'Placeholder');
			Assert.areEqual(0, household.Member_Count__c, 'Nobody in it yet');
		}
	}

	/** Someone who cannot create accounts is not offered the button and is refused plainly. */
	@IsTest
	static void newHouseholdIsRefusedToSomeoneWhoCannotCreateAccounts() {
		System.runAs(TestUsers.admin()) {
			User reader = TestUsers.peopleReaderWith('Hubreader', new List<String>());
			Integer before = [SELECT COUNT() FROM Account WITH SYSTEM_MODE];
			Boolean offered;
			String message;

			Test.startTest();
			System.runAs(reader) {
				offered = HubController.getHomeModel().canCreateHousehold;
				try {
					HubController.createHousehold();
				} catch (AuraHandledException refused) {
					message = refused.getMessage();
				}
			}
			Test.stopTest();

			Assert.isFalse(offered, 'No button');
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_Households_ErrorCreateNoAccess'),
				message,
				'Refused'
			);
			Assert.areEqual(
				before,
				[SELECT COUNT() FROM Account WITH SYSTEM_MODE],
				'Nothing was created'
			);
		}
	}

	@IsTest
	static void tellsMariaWhatToDoNext() {
		System.runAs(TestUsers.admin()) {
			SetupAssistantTestExtension.useNone();

			Test.startTest();
			HubController.HomeModel model = HubController.getHomeModel();
			Test.stopTest();

			Assert.areEqual(8, model.stepsTotal, 'On Core alone the checklist has eight steps');
			Assert.isNotNull(model.stepsCompleted, 'The page says how many are done');
			Assert.isFalse(model.automationPaused, 'Nothing is paused on a fresh org');
			Assert.areEqual(0, model.newErrorCount, 'A fresh org has nothing to review');
			Assert.isFalse(model.newErrorCountCapped, 'Zero is an exact count');
		}
	}

	@IsTest
	static void aFloodedErrorLogShowsTheCapAndSaysThereAreMore() {
		System.runAs(TestUsers.admin()) {
			SetupAssistantTestExtension.useNone();
			List<Error_Log__c> errors = new List<Error_Log__c>();
			for (Integer i = 0; i < 3; i++) {
				errors.add(
					new Error_Log__c(
						Timestamp__c = System.now(),
						Context__c = 'Hub test',
						Message__c = 'Something went wrong.',
						Severity__c = 'Error',
						Status__c = 'New'
					)
				);
			}
			insert errors;
			HubController.errorCountCap = 2;
			User maria = HealthCheckTestHelper.mariaWithManageSettings();

			System.runAs(maria) {
				HubController.HomeModel model = HubController.getHomeModel();
				Assert.areEqual(2, model.newErrorCount, 'The tile shows the cap');
				Assert.isTrue(model.newErrorCountCapped, 'and says there are more than that');
				Assert.areEqual(
					0,
					model.installProblemCount,
					'Errors from elsewhere are not install problems, and the count arrives in the same model'
				);
			}

		}
	}

	@IsTest
	static void letsDavidReadTheHomePageWithoutChangingAnything() {
		System.runAs(TestUsers.admin()) {
			SetupAssistantTestExtension.useNone();
			User david = buildDavid();
			System.runAs(new User(Id = UserInfo.getUserId())) {
				insert david;
			}

			Test.startTest();
			System.runAs(david) {
				HubController.HomeModel model = HubController.getHomeModel();
				Assert.isFalse(model.canEdit, 'David may not change anything');
				Assert.areEqual(
					0,
					model.stepsTotal,
					'The checklist is hidden from David, so its steps are not worked out for him'
				);
				Assert.areEqual(0, model.newErrorCount, 'Nor is the administrator error count');
				Assert.isNull(model.installProblemCount, 'Nor the install problem count');
				Assert.isFalse(model.rollupsStale, 'The admin tiles read as quiet, not broken');
				Assert.isFalse(model.seasonalAddressStale, 'Both of them');
				Assert.isNotNull(model.recurringSources, 'What staff do see still arrives');
			}
			Test.stopTest();
		}
	}

	/**
	 * Home (people-giving-7, D-200 R7): New Person for someone who can create contacts, and
	 * Quick Links from the catalog rows of the modules that are here, nothing for one that
	 * is not.
	 */
	@IsTest
	static void offersNewPersonAndQuickLinksOnlyFromModulesThatAreHere() {
		System.runAs(TestUsers.admin()) {
			SetupAssistantTestExtension.useNone();
			ModuleDetectionService.catalogOverride = new List<BarnCRM_Module__mdt>{
				// Core's own object stands in for a module's probe object, so the row is here.
				new BarnCRM_Module__mdt(
					DeveloperName = 'Here',
					Probe_Object__c = 'Import_Batch__c',
					Quick_Links__c = 'Some_Tab:Do It:One line.;Import_Batch__c.new:Start One'
				),
				new BarnCRM_Module__mdt(
					DeveloperName = 'Absent',
					Probe_Object__c = 'No_Such_Object__c',
					Quick_Links__c = 'Other_Tab:Never Shown:No.'
				)
			};
			Test.startTest();
			HubController.HomeModel model = HubController.getHomeModel();
			Test.stopTest();

			Assert.isTrue(model.canCreatePerson, 'The admin can create people');
			Assert.areEqual(
				2,
				model.quickLinks.size(),
				'Only the module that is here: ' + model.quickLinks
			);
			Assert.areEqual('Some_Tab', model.quickLinks[0].tab, 'A tab link keeps its name');
			Assert.areEqual('Do It', model.quickLinks[0].label, 'With its label');
			Assert.areEqual('One line.', model.quickLinks[0].line, 'And its line');
			Assert.areEqual(
				Schema.SObjectType.Import_Batch__c.getName(),
				model.quickLinks[1].objectApiName,
				'A .new link opens the qualified object'
			);
			Assert.isNull(model.quickLinks[1].line, 'A line is optional');
		}
	}

	@IsTest
	static void aBlankOrUncreatableEntryIsNoLink() {
		System.runAs(TestUsers.admin()) {
			Assert.isNull(HubController.quickLink(''), 'Blank');
			Assert.isNull(HubController.quickLink('Only_A_Target'), 'No label');
			Assert.isNull(HubController.quickLink('No_Such_Object__c.new:New'), 'No such object');
		}
	}

	@IsTest
	static void listsTheFilesThatArriveRegularly() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.defaultSettings();
			Import_Template__c template = ImportTestDataFactory.template(
				ImportTestDataFactory.donorMapping(),
				ImportTemplateService.RULE_EMAIL
			);
			ImportTemplateService.saveRecurring(template.Id, true, 'Monthly processor export');

			Test.startTest();
			HubController.HomeModel model = HubController.getHomeModel();
			Test.stopTest();

			Assert.areEqual(1, model.recurringSources.size(), 'The recurring source is listed.');
			Assert.areEqual(
				'Monthly processor export',
				model.recurringSources[0].sourceName,
				'By the name Maria gave it.'
			);
			Assert.isNull(model.recurringSources[0].lastImportDate, 'Never imported yet.');
		}
	}

	@IsTest
	static void showsTheLastSeasonalSwapAndTheRollupFreshness() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.defaultSettings();
			Datetime finished = Datetime.now().addHours(-2);
			SeasonalAddressWriter.recordRun(finished, '3 moved in, 1 moved back, 0 failed.');
			RollupEngineExtensions.extensionOverride = new StubEngine();

			Test.startTest();
			HubController.HomeModel model = HubController.getHomeModel();
			Test.stopTest();

			Assert.areEqual(finished, model.seasonalAddressLastRun, 'When the swap last ran');
			Assert.areEqual(
				'3 moved in, 1 moved back, 0 failed.',
				model.seasonalAddressLastRunSummary,
				'and what it did'
			);
			Assert.areEqual(
				SeasonalAddressScheduler.isScheduled(),
				model.seasonalAddressScheduled,
				'Whether the nightly swap is scheduled'
			);
			Assert.isFalse(model.seasonalAddressStale, 'A run two hours ago is not stale');
			Assert.isTrue(model.rollupsInstalled, 'The Rollup Builder module answers');
			Assert.areEqual(
				STUB_LAST_CALCULATED,
				model.rollupsLastCalculated,
				'When the rollups last completed'
			);
			Assert.isTrue(model.rollupsStale, 'and whether that is too long ago');
		}
	}

	@IsTest
	static void withoutTheRollupBuilderModuleThereIsNoRollupTile() {
		System.runAs(TestUsers.admin()) {
			SetupAssistantTestExtension.useNone();
			RollupEngineExtensions.noneForTest = true;

			Test.startTest();
			HubController.HomeModel model = HubController.getHomeModel();
			Test.stopTest();

			Assert.isFalse(model.rollupsInstalled, 'No module, no tile');
			Assert.isNull(model.rollupsLastCalculated, 'and nothing to show');
			Assert.isFalse(model.rollupsStale, 'and no false alarm');
		}
	}

	private static final Datetime STUB_LAST_CALCULATED = Datetime.newInstanceGmt(
		2026,
		10,
		1,
		2,
		0,
		0
	);

	/** Stands in for the Rollup Builder module's engine, which Core cannot name. */
	private class StubEngine implements RollupEngineExtension {
		public void afterModuleTurnedOn(String moduleName) {
		}
		public void afterSettingsSaved(String settingsObject, Set<String> changedKeys) {
		}
		public void afterMerge(String targetObject, List<SObject> mergedRecords) {
		}
		public void forSurvivors(String targetObject, Set<Id> survivorIds) {
		}
		public void startQueuedRecalculation() {
		}
		public void processPending() {
		}
		public Datetime lastCalculated() {
			return STUB_LAST_CALCULATED;
		}
		public Boolean isStale() {
			return true;
		}
		public Map<String, Set<String>> targetFieldsByObject() {
			return new Map<String, Set<String>>();
		}
	}

	@IsTest
	static void aTileThatCannotAnswerIsLostNotThePage() {
		System.runAs(TestUsers.admin()) {
			SetupAssistantTestExtension.useNone();
			TestDataFactory.defaultSettings();
			SeasonalAddressWriter.recordRun(Datetime.now(), 'Nothing to swap.');
			HubController.failingPartsForTest = new Set<String>{
				HubController.PART_ROLLUPS,
				HubController.PART_SEASONAL
			};

			Test.startTest();
			HubController.HomeModel model = HubController.getHomeModel();
			Test.stopTest();

			Assert.isNotNull(model, 'The page still loads');
			Assert.areEqual(8, model.stepsTotal, 'with its checklist');
			Assert.isNull(model.rollupsLastCalculated, 'The rollup tile has nothing to show');
			Assert.isFalse(model.rollupsStale, 'and raises no false alarm');
			Assert.isNull(model.seasonalAddressLastRun, 'Nor does the seasonal tile');
			Assert.isFalse(model.seasonalAddressScheduled, 'It does not claim a schedule');
			Assert.isFalse(model.seasonalAddressStale, 'or a missed run');
		}
	}
}
