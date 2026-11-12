/**
 * Territory runs (R-TM3, R-TM4): the first matching rule in priority order wins, Preview changes
 * nothing, Assign moves records and routes their owners as a journaled Data job, and a rule that
 * cannot run stops the run with its reason.
 */
@IsTest(testFor='ApexClass:TerritoryRunBatch')
private class TerritoryRunBatchTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Territory_Admin');
	}

	private static String lastNameIs(String value) {
		return '{"version": 1, "conditions": [{"id": 1, "field": "LastName", "operator": "equals", "value": "' +
			value +
			'"}]}';
	}

	private static Territory__c territory(String name, Integer priority, String routing) {
		Territory__c made = new Territory__c(
			Name = name,
			Priority__c = priority,
			Routing__c = routing
		);
		insert as user made;
		return made;
	}

	private static void rule(Territory__c owner, String filterJson) {
		insert as user new Territory_Rule__c(
			Territory__c = owner.Id,
			Applies_To__c = TerritoryRunBatch.KIND_PEOPLE,
			Filter_JSON__c = filterJson,
			Active__c = true
		);
	}

	private static Territory_Run__c runOf(Id runId) {
		return [
			SELECT
				Status__c,
				Checked__c,
				Changes__c,
				Failed__c,
				Summary_JSON__c,
				Data_Job_Id__c,
				Message__c
			FROM Territory_Run__c
			WHERE Id = :runId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void previewCountsTheFirstMatchAndChangesNothing() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			Territory__c north = territory('North', 10, TerritoryRouting.KEEP_OWNER);
			Territory__c wide = territory('Wide', 20, TerritoryRouting.KEEP_OWNER);
			rule(north, lastNameIs('Alvarez'));
			rule(wide, null);
			insert as user new List<Contact>{
				new Contact(LastName = 'Alvarez'),
				new Contact(LastName = 'Brooks')
			};

			Test.startTest();
			Id runId = TerritoryRunBatch.launch(
				TerritoryRunBatch.MODE_PREVIEW,
				false,
				TerritoryRunBatch.kindsToRun()
			);
			Test.stopTest();

			Territory_Run__c run = runOf(runId);
			Assert.areEqual(TerritoryRunBatch.STATUS_DONE, run.Status__c, run.Message__c);
			Assert.areEqual(2, run.Changes__c, 'Both would move');
			Assert.isNull(run.Data_Job_Id__c, 'A preview has no Data job');
			Assert.isTrue(run.Summary_JSON__c.contains('North'), 'Named in the summary');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Contact WHERE Territory__c != NULL WITH SYSTEM_MODE],
				'Nothing moved'
			);
		}
	}

	@IsTest
	static void assignMovesRoutesAndJournals() {
		User admin = TestUsers.adminWith('Territory_Admin');
		System.runAs(admin) {
			Territory__c north = territory('North', 10, TerritoryRouting.TERRITORY_OWNER);
			north.Owner_User__c = admin.Id;
			update as user north;
			rule(north, lastNameIs('Alvarez'));
			insert as user new List<Contact>{
				new Contact(LastName = 'Alvarez'),
				new Contact(LastName = 'Brooks')
			};

			Test.startTest();
			Id runId = TerritoryRunBatch.launch(
				TerritoryRunBatch.MODE_ASSIGN,
				true,
				TerritoryRunBatch.kindsToRun()
			);
			Test.stopTest();

			Territory_Run__c run = runOf(runId);
			Assert.areEqual(TerritoryRunBatch.STATUS_DONE, run.Status__c, run.Message__c);
			Assert.areEqual(1, run.Changes__c, 'Only Alvarez matches');
			Contact moved = [
				SELECT Territory__c, OwnerId
				FROM Contact
				WHERE LastName = 'Alvarez'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(north.Id, moved.Territory__c, 'Moved in');
			Assert.areEqual(admin.Id, moved.OwnerId, 'Owned by the territory owner');
			Import_Batch__c job = [
				SELECT Status__c, Rows_Updated__c
				FROM Import_Batch__c
				WHERE Id = :run.Data_Job_Id__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, 'Job complete');
			Assert.areEqual(1, job.Rows_Updated__c, 'One saved');
			Assert.areEqual(
				1,
				ImportJournalService.actionCount(
					job.Id,
					ImportJournalService.PHASE_COMMIT,
					ImportJournalService.ACTION_UPDATED
				),
				'Journaled for the undo'
			);
		}
	}

	@IsTest
	static void aRuleThatCannotRunIsRefusedWithItsName() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			Territory__c north = territory('North', 10, TerritoryRouting.KEEP_OWNER);
			rule(
				north,
				'{"version": 1, "conditions": [{"id": 1, "field": "No_Such_Field__c", "operator": "equals", "value": "x"}]}'
			);

			try {
				TerritoryRunBatch.kindsToRun();
				Assert.fail('Refused');
			} catch (TerritoryRunBatch.TerritoryException refused) {
				Assert.isTrue(refused.getMessage().contains('TR-'), refused.getMessage());
			}
			Assert.isFalse(TerritoryRunBatch.busy(), 'Nothing queued');
		}
	}

	@IsTest
	static void aKindWithManyRulesReadsSmallerChunksAndStaysInTheQueryLimit() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			Territory__c wide = territory('Wide', 10, TerritoryRouting.KEEP_OWNER);
			for (Integer i = 0; i < TerritoryRunBatch.MAX_RULES; i++) {
				rule(wide, lastNameIs('NoMatch' + i));
			}
			List<Contact> people = new List<Contact>();
			for (Integer i = 0; i < 200; i++) {
				people.add(new Contact(LastName = 'Person' + i));
			}
			insert as user people;
			Assert.areEqual(
				TerritoryRunBatch.CHUNK_MANY_RULES,
				TerritoryRunBatch.chunkFor(TerritoryRunBatch.KIND_PEOPLE),
				'Many rules, small chunk'
			);

			Test.startTest();
			Id runId = TerritoryRunBatch.launch(
				TerritoryRunBatch.MODE_PREVIEW,
				false,
				TerritoryRunBatch.kindsToRun()
			);
			Test.stopTest();

			Territory_Run__c run = runOf(runId);
			Assert.areEqual(TerritoryRunBatch.STATUS_DONE, run.Status__c, run.Message__c);
			Assert.isTrue(run.Checked__c <= TerritoryRunBatch.CHUNK_MANY_RULES, 'One small chunk');
		}
	}

	@IsTest
	static void aKindWithFewRulesReadsFullChunks() {
		System.runAs(TestUsers.adminWith('Territory_Admin')) {
			rule(territory('North', 10, TerritoryRouting.KEEP_OWNER), lastNameIs('Alvarez'));
			Assert.areEqual(
				TerritoryRunBatch.CHUNK,
				TerritoryRunBatch.chunkFor(TerritoryRunBatch.KIND_PEOPLE)
			);
		}
	}

	@IsTest
	static void poolsCountWhatMembersAlreadyOwn() {
		User admin = TestUsers.adminWith('Territory_Admin');
		System.runAs(admin) {
			Territory__c north = territory('North', 10, TerritoryRouting.CAPACITY);
			insert as user new Territory_Member__c(
				Territory__c = north.Id,
				User__c = admin.Id,
				Capacity__c = 5,
				Active__c = true
			);
			insert as user new Contact(LastName = 'Alvarez', Territory__c = north.Id);

			TerritoryRouting.Pool pool = TerritoryRunBatch.loadPools().get(north.Id);

			Assert.areEqual(1, pool.owned.get(admin.Id), 'One already held');
			Assert.areEqual(admin.Id, TerritoryRouting.ownerFor(pool), 'Room for more');
		}
	}
}
