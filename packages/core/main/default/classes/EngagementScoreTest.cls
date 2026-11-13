/**
 * The engagement score (C-64, canonical model R-ES1 to R-ES5): the settings lines, the
 * arithmetic, signals found by name, and the nightly step. No module is present in Core's
 * tests, so stub signals are injected by class name.
 */
@IsTest(
	testFor='ApexClass:EngagementScore, ApexClass:EngagementScoreJob, ApexClass:EngagementScoreController'
)
private class EngagementScoreTest {
	private static final Date TODAY = Date.newInstance(2026, 11, 11);
	private static final String GIVING = 'GivingEngagementSignal';
	private static final String HOURS = 'VolunteersEngagementSignal';

	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.defaultSettings();
		}
	}

	/** Answers the same total for every person asked about. */
	private class StubSignal implements EngagementSignalExtension {
		private final String part;
		private final Decimal total;
		StubSignal(String part, Decimal total) {
			this.part = part;
			this.total = total;
		}
		public String key() {
			return part;
		}
		public Map<Id, Decimal> totals(Set<Id> contactIds, Date since) {
			Map<Id, Decimal> answer = new Map<Id, Decimal>();
			for (Id contactId : contactIds) {
				answer.put(contactId, total);
			}
			return answer;
		}
	}

	private class FailingSignal implements EngagementSignalExtension {
		public String key() {
			return 'Gifts';
		}
		public Map<Id, Decimal> totals(Set<Id> contactIds, Date since) {
			throw new System.QueryException('The signal could not answer');
		}
	}

	/** A person in memory with a last activity, for the arithmetic alone. */
	private static Contact person(Integer n, Date lastActivity) {
		Map<String, Object> fields = new Map<String, Object>{
			'attributes' => new Map<String, Object>{ 'type' => 'Contact' },
			'Id' => FakeIds.of(Contact.SObjectType, n),
			'LastActivityDate' => lastActivity
		};
		return (Contact) JSON.deserialize(JSON.serialize(fields), Contact.class);
	}

	private static void signals(Map<String, EngagementSignalExtension> registered) {
		EngagementScore.noneForTest = true;
		EngagementScore.overrides = registered;
	}

	private static void turnOn(String weights) {
		BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
		settings.Engagement_Score_Enabled__c = true;
		settings.Engagement_Score_Weights__c = weights;
		TestDataFactory.saveSettings(settings);
	}

	@IsTest
	static void aMissingOrUnreadablePartKeepsItsDefaultAndMonthsIsHeldInRange() {
		System.runAs(TestUsers.admin()) {
			EngagementScore score = new EngagementScore(
				'hours 10; Gifts -5, Events x, Bogus 9',
				'Months 99, Gifts 0'
			);
			Assert.areEqual(
				10,
				score.weights.get('Hours'),
				'A part written in any case and with semicolons is read'
			);
			Assert.areEqual(40, score.weights.get('Gifts'), 'A negative weight keeps the default');
			Assert.areEqual(
				20,
				score.weights.get('Events'),
				'An unreadable number keeps the default'
			);
			Assert.isFalse(score.weights.containsKey('Bogus'), 'An unknown part is ignored');
			Assert.areEqual(60, score.targets.get('Months'), 'Months is held at 60 at most');
			Assert.areEqual(1000, score.targets.get('Gifts'), 'A target must be above 0');
			Assert.areEqual(
				TODAY.addMonths(-60),
				score.since(TODAY),
				'The window starts Months months back'
			);

			EngagementScore shipped = new EngagementScore(null, '');
			Assert.areEqual(
				15,
				shipped.weights.get('Activity'),
				'Empty settings read as the defaults'
			);
			Assert.areEqual(
				90,
				shipped.targets.get('Activity'),
				'Empty settings read as the defaults'
			);
		}
	}

	@IsTest
	static void withNoModuleTheScoreIsActivityAlone() {
		System.runAs(TestUsers.admin()) {
			signals(new Map<String, EngagementSignalExtension>());
			EngagementScore score = new EngagementScore(null, null);
			Map<Id, Integer> scores = score.scores(
				new List<Contact>{
					person(1, TODAY),
					person(2, TODAY.addDays(-45)),
					person(3, null),
					person(4, TODAY.addDays(-200))
				},
				TODAY
			);
			Assert.areEqual(
				100,
				scores.get(FakeIds.of(Contact.SObjectType, 1)),
				'Activity today is full marks'
			);
			Assert.areEqual(
				50,
				scores.get(FakeIds.of(Contact.SObjectType, 2)),
				'Halfway through 90 days is half'
			);
			Assert.areEqual(0, scores.get(FakeIds.of(Contact.SObjectType, 3)), 'No activity is 0');
			Assert.areEqual(
				0,
				scores.get(FakeIds.of(Contact.SObjectType, 4)),
				'Activity older than 90 days is 0'
			);
		}
	}

	@IsTest
	static void installedPartsAreWeightedAndCappedAndAZeroWeightLeavesAPartOut() {
		System.runAs(TestUsers.admin()) {
			signals(
				new Map<String, EngagementSignalExtension>{
					GIVING => new StubSignal('Gifts', 500),
					HOURS => new StubSignal('Hours', 400)
				}
			);
			Contact ana = person(1, TODAY.addDays(-45));
			// Gifts 0.5 x 40 + Hours 1 x 25 (capped) + Activity 0.5 x 15 over 40 + 25 + 15.
			Assert.areEqual(
				66,
				new EngagementScore(null, null).scores(new List<Contact>{ ana }, TODAY).get(ana.Id),
				'52.5 out of 80 rounds to 66; Events is not installed and is left out'
			);
			Assert.areEqual(
				50,
				new EngagementScore('Hours 0, Activity 0', null)
					.scores(new List<Contact>{ ana }, TODAY)
					.get(ana.Id),
				'Only Gifts weighs anything, at one half'
			);
			Assert.areEqual(
				0,
				new EngagementScore('Gifts 0, Hours 0, Activity 0', null)
					.scores(new List<Contact>{ ana }, TODAY)
					.get(ana.Id),
				'No weight at all scores 0'
			);
		}
	}

	@IsTest
	static void signalsAreFoundByNameAndAnUnusableOneThrows() {
		System.runAs(TestUsers.admin()) {
			Contact ana = person(1, TODAY);
			EngagementScore.SIGNAL_CLASSES.clear();
			EngagementScore.SIGNAL_CLASSES.add('NoSuchClassAnywhere');
			Assert.areEqual(
				100,
				new EngagementScore(null, null).scores(new List<Contact>{ ana }, TODAY).get(ana.Id),
				'A signal that is not installed is absent'
			);
			EngagementScore.SIGNAL_CLASSES.add('ExtensionFakeNotAnExtension');
			try {
				new EngagementScore(null, null).scores(new List<Contact>{ ana }, TODAY);
				Assert.fail('An installed class that is not a signal must not be skipped quietly');
			} catch (EngagementScore.SignalException expected) {
				Assert.isTrue(
					expected.getMessage().contains('ExtensionFakeNotAnExtension'),
					'The message names the class'
				);
			}
		}
	}

	@IsTest
	static void theNightlyStepSavesChangedScoresOnlyAndIsActiveWhileOn() {
		System.runAs(TestUsers.admin()) {
			signals(
				new Map<String, EngagementSignalExtension>{
					GIVING => new StubSignal('Gifts', 1000)
				}
			);
			Assert.isFalse(EngagementScoreJob.step().active, 'Off until turned on');
			Assert.isFalse(EngagementScoreController.isFeatureOn(), 'The meter hides while off');
			turnOn('Gifts 40, Activity 0');
			Assert.isTrue(EngagementScoreJob.step().active, 'Active once turned on');
			Assert.isTrue(EngagementScoreController.isFeatureOn(), 'The meter shows while on');
			List<Contact> people = new List<Contact>();
			for (Integer i = 0; i < 20; i++) {
				people.add(TestDataFactory.person(new Contact(LastName = 'Scored' + i)));
			}
			insert people;
			Contact unchanged = people[0];
			unchanged.Engagement_Score__c = 100;
			Database.update(unchanged, AccessLevel.SYSTEM_MODE);

			Test.startTest();
			Database.executeBatch(new EngagementScoreJob(), EngagementScoreJob.CHUNK_SIZE);
			Test.stopTest();

			List<Contact> scored = [
				SELECT Id, Engagement_Score__c, Engagement_Scored_On__c
				FROM Contact
				WHERE LastName LIKE 'Scored%'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(20, scored.size(), 'Every person is read');
			for (Contact each : scored) {
				Assert.areEqual(
					100,
					each.Engagement_Score__c,
					'Full gifts, the only weighted part'
				);
				Assert.areEqual(
					each.Id == unchanged.Id ? null : Date.today(),
					each.Engagement_Scored_On__c,
					'Only a changed score is saved, with today as Scored On'
				);
			}
		}
	}

	@IsTest
	static void aChunkWhoseSignalFailsIsLoggedAndNoOneIsRescored() {
		System.runAs(TestUsers.admin()) {
			signals(new Map<String, EngagementSignalExtension>{ GIVING => new FailingSignal() });
			turnOn(null);
			insert TestDataFactory.person(new Contact(LastName = 'Unscored'));

			Test.startTest();
			Database.executeBatch(new EngagementScoreJob(), EngagementScoreJob.CHUNK_SIZE);
			Test.stopTest();

			Assert.isNull(
				[
					SELECT Engagement_Score__c
					FROM Contact
					WHERE LastName = 'Unscored'
					WITH SYSTEM_MODE
				]
				.Engagement_Score__c,
				'No one is scored without a part that could not answer'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'EngagementScoreJob'
					WITH SYSTEM_MODE
				],
				'The failure is logged'
			);
		}
	}
}
