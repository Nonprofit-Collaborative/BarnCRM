/**
 * SampleDataRemoveBatch: the removal runs its stages the way a load does, under its own class
 * name, and tells the person who removed the sample data when a stage stopped (ADMIN-3, Q-04).
 */
@IsTest(testFor='ApexClass:SampleDataRemoveBatch')
private class SampleDataRemoveBatchTest {
	private static final String STAGE_FAILED = 'stage stopped';
	private static List<Integer> stagesRun = new List<Integer>();
	private static Integer finishes = 0;

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** A removal of two stages; the one named fails, or none does. */
	private class Stages implements SampleDataStages {
		private final Integer failingStage;

		Stages(Integer failingStage) {
			this.failingStage = failingStage;
		}

		public String name() {
			return 'Removal stand-in';
		}

		public Integer stageCount() {
			return 2;
		}

		public void runStage(Integer stage) {
			if (stage == failingStage) {
				throw new IllegalArgumentException(STAGE_FAILED);
			}
			stagesRun.add(stage);
		}

		public void finish() {
			finishes++;
		}
	}

	@IsTest
	static void startRemovalRunsUnderItsOwnClassName() {
		System.runAs(TestUsers.admin()) {
			SampleDataStages removal = new Stages(-1);

			Test.startTest();
			Id jobId = SampleDataRemoveBatch.startRemoval(removal);
			Test.stopTest();

			Assert.isNotNull(jobId, 'A job was started');
			Assert.areEqual(
				'SampleDataRemoveBatch',
				[SELECT ApexClass.Name FROM AsyncApexJob WHERE Id = :jobId].ApexClass.Name,
				'The status card tells a removal from a load by this name'
			);
			Assert.isTrue(SampleDataStageBatch.started.contains(removal), 'The run was noted');
			Assert.areEqual(new List<Integer>{ 0 }, stagesRun, 'A test runs the first stage alone');
		}
	}

	@IsTest
	static void aRemovalThatWorkedSaysNothingAndHandsOver() {
		System.runAs(TestUsers.admin()) {
			SettingsService.setForTest('Job_Notifications__c', true);
			SampleDataRemoveBatch batch = new SampleDataRemoveBatch(new Stages(-1));
			SampleDataStageBatch.everyStageInTest = true;

			batch.start(null);
			batch.runStage(0);
			batch.runStage(1);
			batch.finish(null);

			Assert.areEqual(new List<Integer>{ 0, 1 }, stagesRun, 'Both stages ran in order');
			Assert.isFalse(batch.stopped, 'Nothing stopped');
			Assert.areEqual(1, finishes, 'The removal handed over once every stage ran');
			Assert.isTrue(JobNotifier.sentNotices().isEmpty(), 'A removal that worked sends no stopped notice');
		}
	}

	@IsTest
	static void aStoppedStageTellsThePersonWhoRemoved() {
		System.runAs(TestUsers.admin()) {
			SettingsService.setForTest('Job_Notifications__c', true);
			SampleDataRemoveBatch batch = new SampleDataRemoveBatch(new Stages(1));
			SampleDataStageBatch.everyStageInTest = true;

			batch.start(null);
			batch.runStage(0);
			batch.runStage(1);
			batch.runStage(0);
			batch.finish(null);

			Assert.isTrue(batch.stopped, 'The stage that threw stopped the removal');
			Assert.areEqual(new List<Integer>{ 0 }, stagesRun, 'No stage ran after the one that failed');
			Assert.areEqual(0, finishes, 'A stopped removal hands over to nothing');
			Assert.areEqual(1, JobNotifier.sentNotices().size(), 'One notice, from the removal');
			JobNotifier.Notice notice = JobNotifier.sentNotices()[0];
			Assert.areEqual(UserInfo.getUserId(), notice.recipientId, 'To the person who removed');
			Assert.areEqual(
				String.format(
					System.Label.Core_JobNotice_Stopped,
					new List<Object>{ System.Label.Core_JobNotice_SampleDataRemove }
				),
				notice.title,
				'Saying the removal stopped, not the load'
			);
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_JobNotice_SampleDataRemoveStoppedBody'),
				notice.body,
				'With the removal wording'
			);
		}
	}
}
