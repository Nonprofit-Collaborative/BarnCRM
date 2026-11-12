/**
 * A logic model's shared reporting periods (canonical model R-LM4; v1.0 modules-23), through the
 * builder's controller: the list saved and checked, Add Period to Every Indicator, Use the
 * Model's Periods, an indicator's own periods kept, and what readers may do.
 */
@IsTest(
	testFor='ApexClass:LogicModelPeriodService, ApexClass:LogicModelBuilderController, ApexClass:LogicModelService'
)
private class LogicModelPeriodServiceTest {
	private static final String ADMIN = 'Logic_Models_Admin';
	private static final String Q1 = '{"name": "2026 Q1", "startDate": "2026-01-01", "endDate": "2026-03-31"}';
	private static final String Q2 = '{"name": "2026 Q2", "startDate": "2026-04-01", "endDate": "2026-06-30"}';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
		TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Logic_Models_Read_Only' }
		);
	}

	/** A model with an output and two indicators; the first already has its own 2026 Q1. */
	private class Fixture {
		Id modelId;
		Id firstId;
		Id secondId;

		Fixture() {
			Logic_Model__c model = new Logic_Model__c(Name = 'Periods Model');
			insert as user model;
			modelId = model.Id;
			Logic_Model_Element__c element = new Logic_Model_Element__c(
				Logic_Model__c = modelId,
				Name = 'Sessions held',
				Type__c = 'Output'
			);
			insert as user element;
			Indicator__c first = new Indicator__c(Element__c = element.Id, Name = 'Sessions');
			Indicator__c second = new Indicator__c(Element__c = element.Id, Name = 'Hours');
			insert as user new List<Indicator__c>{ first, second };
			firstId = first.Id;
			secondId = second.Id;
			insert as user new Indicator_Period__c(
				Indicator__c = firstId,
				Name = 'First quarter',
				Start_Date__c = Date.newInstance(2026, 1, 1),
				End_Date__c = Date.newInstance(2026, 3, 31),
				Target_Value__c = 10
			);
		}
	}

	private static Integer periodCount(Id indicatorId) {
		return [
			SELECT COUNT()
			FROM Indicator_Period__c
			WHERE Indicator__c = :indicatorId
			WITH SYSTEM_MODE
		];
	}

	private static String refusal(Id modelId, String periodsJson) {
		try {
			LogicModelBuilderController.savePeriods(modelId, periodsJson);
		} catch (AuraHandledException e) {
			return e.getMessage();
		}
		return null;
	}

	@IsTest
	static void theListIsSavedInStartOrderAndRead() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Fixture fixture = new Fixture();

			Test.startTest();
			Map<String, Object> model = LogicModelBuilderController.savePeriods(
				fixture.modelId,
				'[' + Q2 + ',' + Q1 + ']'
			);
			Test.stopTest();

			List<Object> periods = (List<Object>) model.get('periods');
			Assert.areEqual(2, periods.size(), 'Both periods');
			Map<String, Object> first = (Map<String, Object>) periods[0];
			Assert.areEqual('2026 Q1', first.get('name'), 'In start date order');
			Assert.areEqual('2026-01-01', first.get('startDate'), 'ISO dates');
			Assert.areEqual(true, model.get('canEditPeriods'), 'An admin changes the list');
		}
	}

	@IsTest
	static void aBadListIsRefusedWithItsReason() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Fixture fixture = new Fixture();

			Test.startTest();
			String noName = refusal(
				fixture.modelId,
				'[{"name": " ", "startDate": "2026-01-01", "endDate": "2026-03-31"}]'
			);
			String backward = refusal(
				fixture.modelId,
				'[{"name": "Odd", "startDate": "2026-03-31", "endDate": "2026-01-01"}]'
			);
			String twice = refusal(
				fixture.modelId,
				'[' +
					Q1 +
					', {"name": "Again", "startDate": "2026-01-01", "endDate": "2026-03-31"}]'
			);
			String notAList = refusal(fixture.modelId, '{"name": "x"}');
			String unreadable = refusal(fixture.modelId, '[{"name": "x", "startDate": "soon"}]');
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('LogicModels', 'LogicModels_Periods_Invalid'),
				noName,
				'A name is needed'
			);
			Assert.isTrue(backward.contains('Odd'), 'An end before the start names the period');
			Assert.isTrue(twice.contains('Again'), 'The same dates twice names the second');
			Assert.areEqual(LogicModelBuilderController.actionFailed(), notAList, 'Not a list');
			Assert.areEqual(
				BarnHelp.text('LogicModels', 'LogicModels_Periods_Invalid'),
				unreadable,
				'A date that is not a date'
			);
			Map<String, Object> model = LogicModelBuilderController.getModel(fixture.modelId);
			Assert.areEqual(0, ((List<Object>) model.get('periods')).size(), 'Nothing saved');
		}
	}

	@IsTest
	static void aPeriodGoesOnEveryIndicatorThatLacksIt() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Fixture fixture = new Fixture();
			LogicModelBuilderController.savePeriods(fixture.modelId, '[' + Q1 + ',' + Q2 + ']');

			Test.startTest();
			Map<String, Object> afterQ1 = LogicModelBuilderController.addPeriodToEveryIndicator(
				fixture.modelId,
				'2026-01-01',
				'2026-03-31'
			);
			Map<String, Object> again = LogicModelBuilderController.addPeriodToEveryIndicator(
				fixture.modelId,
				'2026-01-01',
				'2026-03-31'
			);
			Test.stopTest();

			Assert.areEqual(1, afterQ1.get('added'), 'Only the indicator without 2026 Q1');
			Assert.areEqual(0, again.get('added'), 'Nothing twice');
			Assert.areEqual(1, periodCount(fixture.firstId), 'Its own period stays, unchanged');
			Indicator_Period__c copied = [
				SELECT Name, Target_Value__c, Result_Value__c
				FROM Indicator_Period__c
				WHERE Indicator__c = :fixture.secondId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('2026 Q1', copied.Name, 'The model period name');
			Assert.isNull(copied.Target_Value__c, 'No target copied');
		}
	}

	@IsTest
	static void anIndicatorTakesEveryModelPeriodItLacks() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Fixture fixture = new Fixture();
			LogicModelBuilderController.savePeriods(fixture.modelId, '[' + Q1 + ',' + Q2 + ']');

			Test.startTest();
			Map<String, Object> model = LogicModelBuilderController.useModelPeriods(
				fixture.modelId,
				fixture.firstId
			);
			Test.stopTest();

			Assert.areEqual(1, model.get('added'), 'Only 2026 Q2: it has its own 2026 Q1');
			Assert.areEqual(2, periodCount(fixture.firstId), 'Two periods now');
			Assert.areEqual(0, periodCount(fixture.secondId), 'The other indicator is untouched');
		}
	}

	@IsTest
	static void anUnknownPeriodOrIndicatorIsRefused() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Fixture fixture = new Fixture();
			delete as user new Indicator__c(Id = fixture.secondId);
			String unknownPeriod;
			String goneIndicator;

			Test.startTest();
			try {
				LogicModelBuilderController.addPeriodToEveryIndicator(
					fixture.modelId,
					'2030-01-01',
					'2030-12-31'
				);
			} catch (AuraHandledException e) {
				unknownPeriod = e.getMessage();
			}
			try {
				LogicModelBuilderController.useModelPeriods(fixture.modelId, fixture.secondId);
			} catch (AuraHandledException e) {
				goneIndicator = e.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('LogicModels', 'LogicModels_Builder_NotFound'),
				unknownPeriod,
				'Not a model period'
			);
			Assert.areEqual(
				BarnHelp.text('LogicModels', 'LogicModels_Builder_NotFound'),
				goneIndicator,
				'Not found'
			);
		}
	}

	@IsTest
	static void aReaderSeesThePeriodsButCannotChangeThem() {
		Id modelId;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			modelId = new Fixture().modelId;
			LogicModelBuilderController.savePeriods(modelId, '[' + Q1 + ']');
		}
		User reader = [SELECT Id FROM User WHERE LastName = 'Reader' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(reader) {
			Test.startTest();
			Map<String, Object> model = LogicModelBuilderController.getModel(modelId);
			String refused = refusal(modelId, '[]');
			Test.stopTest();

			Assert.areEqual(1, ((List<Object>) model.get('periods')).size(), 'Read');
			Assert.areEqual(false, model.get('canEditPeriods'), 'Not changeable');
			Assert.isNotNull(refused, 'A save is refused');
		}
	}

	@IsTest
	static void unreadableStoredTextReadsAsNoPeriods() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Test.startTest();
			Integer unreadable = LogicModelPeriodService.parse('not json').size();
			Integer blank = LogicModelPeriodService.parse(null).size();
			Test.stopTest();

			Assert.areEqual(0, unreadable, 'Unreadable');
			Assert.areEqual(0, blank, 'Blank');
		}
	}
}
