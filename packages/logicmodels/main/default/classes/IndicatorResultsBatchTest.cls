/**
 * Computed indicator results (L-03, canonical model R-IN5 and R-IN6): count, sum and count unique
 * per started period, periods that overlap, a period not yet started left alone, records the
 * runner cannot see still counted (system mode), a missing query reported in Source Status, and
 * the nightly job Health Check schedules.
 *
 * The source records are Indicator Periods of two "data" indicators (named Session) and, for the
 * sharing case, saved queries, so the test needs no other module.
 */
@IsTest(
	testFor='ApexClass:IndicatorResultsBatch, ApexClass:IndicatorResultsScheduler, ApexClass:LogicModelsNightlyJobProvider'
)
private class IndicatorResultsBatchTest {
	private static final String ADMIN = 'Logic_Models_Admin';
	private static final String SESSIONS =
		'{"version": 1, "object": "Indicator_Period__c", "fields": ["Name"], ' +
		'"filter": {"version": 1, "conditions": [{"id": 1, "field": "Name", "operator": "equals", "value": "Session"}]}}';
	private static final String COUNTED_QUERIES =
		'{"version": 1, "object": "Saved_Query__c", "fields": ["Name"], ' +
		'"filter": {"version": 1, "conditions": [{"id": 1, "field": "Name", "operator": "equals", "value": "Counted"}]}}';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
	}

	/** The first day of the month six months ago: every period below has started. */
	private static Date base() {
		return Date.today().addMonths(-6).toStartOfMonth();
	}

	private static Id newElement() {
		Logic_Model__c model = new Logic_Model__c(Name = 'Results Model');
		insert as user model;
		Logic_Model_Element__c element = new Logic_Model_Element__c(
			Logic_Model__c = model.Id,
			Name = 'Sessions held',
			Type__c = 'Output'
		);
		insert as user element;
		return element.Id;
	}

	/**
	 * Two data indicators whose Session periods are the records counted: A has three (base + 4,
	 * base + 19, next month + 9) and one after the quarter, B one (base + 4).
	 */
	private static void sessions(Id elementId) {
		Indicator__c dataA = new Indicator__c(Element__c = elementId, Name = 'Data A');
		Indicator__c dataB = new Indicator__c(Element__c = elementId, Name = 'Data B');
		insert as user new List<Indicator__c>{ dataA, dataB };
		Date start = base();
		insert as user new List<Indicator_Period__c>{
			session(dataA.Id, start.addDays(4), 2),
			session(dataA.Id, start.addDays(19), 3),
			session(dataA.Id, start.addMonths(1).addDays(9), 5),
			session(dataA.Id, start.addMonths(4), 7),
			session(dataB.Id, start.addDays(4), 4)
		};
	}

	private static Indicator_Period__c session(Id indicatorId, Date day, Decimal value) {
		return new Indicator_Period__c(
			Indicator__c = indicatorId,
			Name = 'Session',
			Start_Date__c = day,
			End_Date__c = day,
			Target_Value__c = value
		);
	}

	/** A computed indicator with a month, a quarter and a period that has not started. */
	private static Id computed(Id elementId, String queryJson, String definition) {
		Saved_Query__c query = new Saved_Query__c(
			Name = 'Source',
			Object_Name__c = 'Indicator_Period__c',
			Query_JSON__c = queryJson
		);
		insert as user query;
		Indicator__c indicator = new Indicator__c(
			Element__c = elementId,
			Name = 'Computed',
			Source__c = 'Computed',
			Source_Query__c = query.Id,
			Source_Definition__c = definition
		);
		insert as user indicator;
		Date start = base();
		insert as user new List<Indicator_Period__c>{
			new Indicator_Period__c(
				Indicator__c = indicator.Id,
				Name = 'Month',
				Start_Date__c = start,
				End_Date__c = start.addMonths(1).addDays(-1)
			),
			new Indicator_Period__c(
				Indicator__c = indicator.Id,
				Name = 'Quarter',
				Start_Date__c = start,
				End_Date__c = start.addMonths(3).addDays(-1)
			),
			new Indicator_Period__c(
				Indicator__c = indicator.Id,
				Name = 'Later',
				Start_Date__c = Date.today().addDays(10),
				End_Date__c = Date.today().addDays(40),
				Result_Value__c = 99
			)
		};
		return indicator.Id;
	}

	private static String definition(String function, String field) {
		return JSON.serialize(
			new Map<String, Object>{
				'version' => 1,
				'dateField' => 'Start_Date__c',
				'function' => function,
				'field' => field
			}
		);
	}

	private static Map<String, Decimal> results(Id indicatorId) {
		Map<String, Decimal> byName = new Map<String, Decimal>();
		for (Indicator_Period__c period : [
			SELECT Name, Result_Value__c
			FROM Indicator_Period__c
			WHERE Indicator__c = :indicatorId
			WITH SYSTEM_MODE
		]) {
			byName.put(period.Name, period.Result_Value__c);
		}
		return byName;
	}

	private static Indicator__c indicator(Id indicatorId) {
		return [
			SELECT Source_Status__c, Computed_At__c
			FROM Indicator__c
			WHERE Id = :indicatorId
			WITH SYSTEM_MODE
		];
	}

	private static Map<String, Decimal> run(String function, String field) {
		Id indicatorId;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Id elementId = newElement();
			sessions(elementId);
			indicatorId = computed(elementId, SESSIONS, definition(function, field));
			Test.startTest();
			IndicatorResultsBatch.run(new List<Id>{ indicatorId });
			Test.stopTest();
		}
		Indicator__c after = indicator(indicatorId);
		Assert.isNull(after.Source_Status__c, 'No problem: ' + after.Source_Status__c);
		Assert.isNotNull(after.Computed_At__c, 'Computed At is set');
		return results(indicatorId);
	}

	@IsTest
	static void aCountPutsEachRecordInEveryPeriodThatHoldsItsDate() {
		// runs-as: deploying user (run() works as the Logic Models admin; the asserts read in system mode)
		Map<String, Decimal> byName = run('count', null);

		Assert.areEqual(3, byName.get('Month'), 'Three sessions in the first month');
		Assert.areEqual(4, byName.get('Quarter'), 'Four in the quarter that overlaps it');
		Assert.areEqual(99, byName.get('Later'), 'A period not started is left alone');
	}

	@IsTest
	static void aSumAddsUpTheField() {
		// runs-as: deploying user (run() works as the Logic Models admin; the asserts read in system mode)
		Map<String, Decimal> byName = run('sum', 'Target_Value__c');

		Assert.areEqual(9, byName.get('Month'), '2 + 3 + 4');
		Assert.areEqual(14, byName.get('Quarter'), '2 + 3 + 4 + 5');
	}

	@IsTest
	static void aUniqueCountCountsEachValueOnce() {
		// runs-as: deploying user (run() works as the Logic Models admin; the asserts read in system mode)
		Map<String, Decimal> byName = run('unique', 'Indicator__c');

		Assert.areEqual(2, byName.get('Month'), 'Two data indicators in the month');
		Assert.areEqual(2, byName.get('Quarter'), 'Still two in the quarter');
	}

	@IsTest
	static void recordsTheRunnerCannotSeeAreCounted() {
		User runner = TestUsers.standardUserWith(
			'Runner',
			new List<String>{ 'BarnCRM_Find_And_Export', 'Logic_Models_Staff' }
		);
		Id indicatorId;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			// Private saved queries of the admin: the runner sees none of them.
			insert as user new List<Saved_Query__c>{
				new Saved_Query__c(
					Name = 'Counted',
					Object_Name__c = 'Contact',
					Query_JSON__c = '{}'
				),
				new Saved_Query__c(
					Name = 'Counted',
					Object_Name__c = 'Contact',
					Query_JSON__c = '{}'
				)
			};
			Id elementId = newElement();
			Saved_Query__c source = new Saved_Query__c(
				Name = 'Source',
				Object_Name__c = 'Saved_Query__c',
				Query_JSON__c = COUNTED_QUERIES
			);
			insert as user source;
			Indicator__c computed = new Indicator__c(
				Element__c = elementId,
				Name = 'Queries saved',
				Source__c = 'Computed',
				Source_Query__c = source.Id,
				Source_Definition__c = JSON.serialize(
					new Map<String, Object>{
						'version' => 1,
						'dateField' => 'CreatedDate',
						'function' => 'count'
					}
				)
			);
			insert as user computed;
			indicatorId = computed.Id;
			insert as user new Indicator_Period__c(
				Indicator__c = indicatorId,
				Name = 'This week',
				Start_Date__c = Date.today().addDays(-1),
				End_Date__c = Date.today().addDays(1)
			);
		}
		Integer seen;
		System.runAs(runner) {
			seen = [SELECT COUNT() FROM Saved_Query__c WHERE Name = 'Counted' WITH USER_MODE];
			Test.startTest();
			IndicatorResultsBatch.run(new List<Id>{ indicatorId });
			Test.stopTest();
		}

		Assert.areEqual(0, seen, 'The runner sees none of the counted records');
		Assert.areEqual(
			2,
			results(indicatorId).get('This week'),
			'The result is the organization\'s figure, not the runner\'s share'
		);
	}

	@IsTest
	static void aDeletedQueryIsReportedAndNoResultChanges() {
		Id indicatorId;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Id elementId = newElement();
			sessions(elementId);
			indicatorId = computed(elementId, SESSIONS, definition('count', null));
			delete as user [SELECT Id FROM Saved_Query__c WITH USER_MODE];
			Test.startTest();
			IndicatorResultsBatch.run(new List<Id>{ indicatorId });
			Test.stopTest();
		}

		Indicator__c after = indicator(indicatorId);
		Assert.areEqual(Label.LogicModels_Source_QueryMissing, after.Source_Status__c, 'Reported');
		Assert.isNull(after.Computed_At__c, 'Not computed');
		Assert.isNull(results(indicatorId).get('Month'), 'No result written');
	}

	@IsTest
	static void aQueryTheRunnerCannotCompileIsReported() {
		Id indicatorId;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Id elementId = newElement();
			indicatorId = computed(
				elementId,
				SESSIONS,
				definition('sum', 'Name') // not a number
			);
			Test.startTest();
			IndicatorResultsBatch.run(new List<Id>{ indicatorId });
			Test.stopTest();
		}

		Assert.isTrue(
			indicator(indicatorId).Source_Status__c.contains('Period'),
			'The field is named: ' + indicator(indicatorId).Source_Status__c
		);
	}

	@IsTest
	static void anIndicatorNoLongerComputedIsLeftAlone() {
		Id indicatorId;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Id elementId = newElement();
			indicatorId = computed(elementId, SESSIONS, definition('count', null));
			update as user new Indicator__c(Id = indicatorId, Source__c = 'Manual');
			Test.startTest();
			IndicatorResultsBatch.run(new List<Id>{ indicatorId });
			Test.stopTest();
		}

		Assert.isNull(indicator(indicatorId).Computed_At__c, 'Nothing written');
		Assert.isNull(IndicatorResultsBatch.run(new List<Id>()), 'Nothing to start');
	}

	@IsTest
	static void theNightlyJobRefreshesEveryComputedIndicatorAndHealthCheckSchedulesIt() {
		IndicatorResultsScheduler.jobNameInUse = 'BarnCRM Indicator Results Test';
		Id indicatorId;
		Id jobId;
		NightlyStep step = new LogicModelsNightlyJobProvider().nightlySteps()[0];
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Id elementId = newElement();
			sessions(elementId);
			indicatorId = computed(elementId, SESSIONS, definition('count', null));
			Test.startTest();
			jobId = IndicatorResultsScheduler.refreshAll();
			Test.stopTest();
		}

		Assert.areEqual(Label.LogicModels_NightlyJobs_ResultsName, step.label, 'Its name');
		Assert.areEqual(210, step.minute, 'At half past three in the nightly run');
		Assert.isNotNull(jobId, 'A run started');
		Assert.areEqual(3, results(indicatorId).get('Month'), 'Worked out');
	}

	@IsTest
	static void theScheduledRunStartsTheRefresh() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Test.startTest();
			new IndicatorResultsScheduler().execute(null);
			Test.stopTest();
		}
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' WITH SYSTEM_MODE],
			'No computed indicator, so no run'
		);
	}

	@IsTest
	static void aFieldPathIsFollowed() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Indicator_Period__c period = new Indicator_Period__c(Name = 'Q1');
			period.putSObject('Indicator__r', new Indicator__c(Name = 'Parent'));

			Assert.areEqual(
				'Parent',
				IndicatorResultsBatch.valueAt(period, 'Indicator__r.Name'),
				'Followed'
			);
			Assert.areEqual('Q1', IndicatorResultsBatch.valueAt(period, 'Name'), 'Direct');
		}
	}
}
