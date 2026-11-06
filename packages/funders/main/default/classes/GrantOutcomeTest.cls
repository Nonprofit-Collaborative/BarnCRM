/**
 * A grant requirement's Logic Models outcome (L-06, canonical model 29ZI R-GQ6): the card offers
 * outcomes and outputs only, saves and clears the choice, shows the indicator periods in the
 * award period and a deleted outcome as missing; the rule refuses what is not an element. Logic
 * Models records are made by describe, so the test compiles where Logic Models is absent, and
 * there proves the card says so.
 */
@IsTest(
	testFor='ApexClass:GrantOutcomeService, ApexClass:GrantOutcomeController, ApexClass:GrantRequirementRulesHandler'
)
private class GrantOutcomeTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWithInstalledModules();
	}

	private static Schema.SObjectType type(String name) {
		return NamespaceUtil.packagedObjectType(name);
	}

	private static SObject record(String objectName, Map<String, Object> values) {
		SObject row = type(objectName).newSObject();
		for (String field : values.keySet()) {
			row.put(
				field.endsWith('__c') ? NamespaceUtil.qualify(field) : field,
				values.get(field)
			);
		}
		return row;
	}

	private static Grant_Requirement__c requirement() {
		Account funder = GrantTestData.funder('Lakeside Foundation');
		Grant__c grant = GrantTestData.grant('Reading', funder.Id, GrantService.STAGE_AWARDED);
		grant.Award_Start_Date__c = Date.newInstance(2026, 1, 1);
		grant.Award_End_Date__c = Date.newInstance(2026, 12, 31);
		insert grant;
		Grant_Requirement__c requirement = GrantTestData.requirement(
			'Final report',
			grant.Id,
			Date.newInstance(2027, 1, 31)
		);
		insert requirement;
		return requirement;
	}

	/** An outcome with one indicator measured in 2024 and in 2026, and an activity. */
	private static Map<String, Id> logicModel() {
		SObject model = record('Logic_Model__c', new Map<String, Object>{ 'Name' => 'Reading' });
		insert model;
		SObject outcome = record(
			'Logic_Model_Element__c',
			new Map<String, Object>{
				'Logic_Model__c' => model.Id,
				'Type__c' => 'Outcome',
				'Outcome_Term__c' => 'Short Term'
			}
		);
		outcome.put('Name', 'Students read at home');
		SObject activity = record(
			'Logic_Model_Element__c',
			new Map<String, Object>{ 'Logic_Model__c' => model.Id, 'Type__c' => 'Activity' }
		);
		activity.put('Name', 'Tutoring sessions');
		insert new List<SObject>{ outcome, activity };
		SObject indicator = record(
			'Indicator__c',
			new Map<String, Object>{ 'Element__c' => outcome.Id, 'Unit__c' => 'students' }
		);
		indicator.put('Name', 'Students reading daily');
		insert indicator;
		List<SObject> periods = new List<SObject>();
		for (Integer year : new List<Integer>{ 2024, 2026 }) {
			SObject period = record(
				'Indicator_Period__c',
				new Map<String, Object>{
					'Indicator__c' => indicator.Id,
					'Start_Date__c' => Date.newInstance(year, 1, 1),
					'End_Date__c' => Date.newInstance(year, 12, 31),
					'Target_Value__c' => 30,
					'Result_Value__c' => 25
				}
			);
			period.put('Name', String.valueOf(year));
			periods.add(period);
		}
		insert periods;
		return new Map<String, Id>{ 'outcome' => outcome.Id, 'activity' => activity.Id };
	}

	private static String stored(Id requirementId) {
		return [
			SELECT Outcome_Id__c
			FROM Grant_Requirement__c
			WHERE Id = :requirementId
			WITH SYSTEM_MODE
		]
		.Outcome_Id__c;
	}

	@IsTest
	static void theCardLinksAnOutcomeAndShowsItsResultsForTheAwardPeriod() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant_Requirement__c requirement = requirement();
			if (type('Logic_Model_Element__c') == null) {
				GrantOutcomeController.OutcomeCard card = GrantOutcomeController.getOutcomes(
					requirement.Grant__c
				);
				Assert.isFalse(card.available, 'Without Logic Models there is nothing to link');
				return;
			}
			Map<String, Id> ids = logicModel();

			Test.startTest();
			GrantOutcomeController.OutcomeCard before = GrantOutcomeController.getOutcomes(
				requirement.Grant__c
			);
			GrantOutcomeController.setOutcome(requirement.Id, String.valueOf(ids.get('outcome')));
			GrantOutcomeController.OutcomeCard after = GrantOutcomeController.getOutcomes(
				requirement.Grant__c
			);
			Test.stopTest();

			Assert.isTrue(before.available, 'Logic Models is there');
			Assert.isTrue(before.canEdit, 'The admin may choose');
			Assert.areEqual(1, before.options.size(), 'Outcomes and outputs only, no activity');
			Assert.areEqual(
				'Reading: Students read at home',
				before.options[0].get('label'),
				'By model'
			);
			Assert.areEqual(1, before.rows.size(), 'The one requirement');
			Assert.isNull(before.rows[0].outcomeId, 'Nothing linked yet');

			GrantOutcomeController.Row row = after.rows[0];
			Assert.areEqual(String.valueOf(ids.get('outcome')), row.outcomeId, 'Saved');
			Assert.isFalse(row.missing, 'Found');
			List<Map<String, Object>> indicators = (List<Map<String, Object>>) row.outcome.get(
				'indicators'
			);
			Assert.areEqual(1, indicators.size(), 'Its indicator');
			Assert.areEqual('students', indicators[0].get('unit'), 'With its unit');
			List<Map<String, Object>> periods = (List<Map<String, Object>>) indicators[0]
				.get('periods');
			Assert.areEqual(1, periods.size(), 'Only the period in the award period');
			Assert.areEqual('2026', periods[0].get('name'), 'The 2026 period');
			Assert.areEqual(25, (Decimal) periods[0].get('result'), 'Its result');

			delete type('Logic_Model_Element__c').newSObject(ids.get('outcome'));
			Assert.isTrue(
				GrantOutcomeController.getOutcomes(requirement.Grant__c).rows[0].missing,
				'A deleted outcome shows as missing'
			);
		}
	}

	@IsTest
	static void onlyAnOutcomeOrOutputCanBeNamed() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant_Requirement__c requirement = requirement();
			Boolean installed = type('Logic_Model_Element__c') != null;
			Map<String, Id> ids = installed ? logicModel() : new Map<String, Id>();

			Test.startTest();
			Database.SaveResult text = Database.update(
				new Grant_Requirement__c(Id = requirement.Id, Outcome_Id__c = 'not an id'),
				false,
				AccessLevel.USER_MODE
			);
			Database.SaveResult grant = Database.update(
				new Grant_Requirement__c(Id = requirement.Id, Outcome_Id__c = requirement.Grant__c),
				false,
				AccessLevel.USER_MODE
			);
			String activityRefusal;
			if (installed) {
				try {
					GrantOutcomeController.setOutcome(
						requirement.Id,
						String.valueOf(ids.get('activity'))
					);
				} catch (AuraHandledException e) {
					activityRefusal = e.getMessage();
				}
				update as user new Grant_Requirement__c(
					Id = requirement.Id,
					Outcome_Id__c = String.valueOf(ids.get('outcome')).left(15)
				);
			}
			Test.stopTest();

			Assert.isFalse(text.isSuccess(), 'Text that is not an identifier is refused');
			Assert.areEqual(
				BarnHelp.text('Funders', 'Funders_Outcomes_NotAnOutcome'),
				text.getErrors()[0].getMessage(),
				'With the rule message'
			);
			if (!installed) {
				return;
			}
			Assert.isFalse(grant.isSuccess(), 'A grant is not an outcome');
			Assert.areEqual(
				BarnHelp.text('Funders', 'Funders_Outcomes_NotAnOutcome'),
				activityRefusal,
				'Nor an activity'
			);
			Assert.areEqual(
				String.valueOf(ids.get('outcome')),
				stored(requirement.Id),
				'Stored in full'
			);
			GrantOutcomeController.setOutcome(requirement.Id, '');
			Assert.isNull(stored(requirement.Id), 'Cleared');
		}
	}
}
