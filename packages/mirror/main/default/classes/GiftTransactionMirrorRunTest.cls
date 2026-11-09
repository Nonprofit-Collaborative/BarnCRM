/**
 * The Gift Transaction mirror's runs, nightly job, reconciliation and Health Check finding (X-07,
 * R-GT6, R-GT10), as Maria sees them.
 *
 * The test org has no Nonprofit Cloud, so the present path runs against the stand-ins of
 * `GiftTransactionMirrorSchema.useStandIns` (ADR-0157 decision 9): Gift for Gift Transaction, and
 * so on. The paid status here is Pending, so the stand-in Gift Transactions, pending gifts, are
 * never themselves gifts the mirror copies. The absent path is forced with `absentForTest`.
 */
@IsTest(
	testFor='ApexClass:GiftTransactionMirrorBatch, ApexClass:GiftTransactionMirrorSchedulable, ApexClass:GiftTransactionMirrorReconciliation, ApexClass:MirrorHealthCheckExtension, ApexClass:MirrorNightlyJobProvider, ApexClass:MirrorSettingsWriter'
)
private class GiftTransactionMirrorRunTest {
	private static final String RUN_CONTEXT = 'Gift Transaction mirror: run';
	private static final Date GIFT_DATE = Date.newInstance(2026, 9, 20);
	private static final String PAID = 'Pending';

	@TestSetup
	static void setup() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.ensureDefaultFund();
			GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
			Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
			settings.Gift_Transaction_Mirror_Direction__c = GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS;
			settings.Gift_Transaction_Mirror_Status__c = PAID;
			settings.Gift_Transaction_Mirror_Start__c = Datetime.newInstance(2026, 1, 1, 12, 0, 0);
			upsert settings;
		}
		// Built once for the class rather than in every test that runs as her.
		TestDataFactory.createUserOnTheRunningUsersProfile(
			'Maria',
			new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Gift_Transaction_Mirror' }
		);
	}

	/** Maria: an administrator who runs the mirror. */
	private static User maria() {
		return TestUsers.fromSetup('Maria');
	}

	private static Gift__c insertGift(Decimal amount) {
		Contact luis = [
			SELECT Id
			FROM Contact
			WHERE LastName = 'Garcia'
			WITH SYSTEM_MODE
			LIMIT 1
		];
		Gift__c gift = GivingTestDataFactory.buildGift(luis.Id, amount);
		gift.Gift_Date__c = GIFT_DATE;
		insert as user gift;
		return reread(gift.Id);
	}

	private static Gift__c reread(Id giftId) {
		return (Gift__c) Database.queryWithBinds(
			'SELECT ' +
				GiftTransactionMirrorSelector.GIFT_FIELDS +
				' FROM Gift__c WHERE Id = :giftId',
			new Map<String, Object>{ 'giftId' => giftId },
			AccessLevel.SYSTEM_MODE
		)[0];
	}

	/** Runs the batch in this transaction: start, one chunk, finish. */
	private static void runInline(GiftTransactionMirrorBatch batch) {
		Database.QueryLocatorIterator found = batch.start(null).iterator();
		List<SObject> scope = new List<SObject>();
		while (found.hasNext()) {
			scope.add(found.next());
		}
		if (!scope.isEmpty()) {
			batch.execute(null, scope);
		}
		batch.finish(null);
	}

	private static List<Error_Log__c> logged(String severity) {
		return [
			SELECT Message__c
			FROM Error_Log__c
			WHERE Context__c = :RUN_CONTEXT AND Severity__c = :severity
			WITH SYSTEM_MODE
		];
	}

	private static void clearOrgJob() {
		TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
		ScheduledJobSelector.forget();
	}

	// -------------------------------------------------------------------------------- runs

	@IsTest
	static void withoutNonprofitCloudARunDoesNothingAndSaysSo() {
		System.runAs(maria()) {
			insertGift(100);
			GiftTransactionMirrorSchema.absentForTest = true;
			Assert.isNull(GiftTransactionMirrorBatch.run(), 'No run starts (R-GT1).');
			Assert.isFalse(
				NightlyJobs.isOn(GiftTransactionMirrorSchedulable.step()),
				'Not in tonight\'s run.'
			);
			Test.startTest();
			runInline(new GiftTransactionMirrorBatch(null, null));
			Test.stopTest();
		}
		List<Error_Log__c> warnings = logged('Warning');
		Assert.areEqual(1, warnings.size());
		Assert.isTrue(warnings[0].Message__c.contains('no Nonprofit Cloud Gift Transactions'));
		Assert.isNull(Mirror_Settings__c.getOrgDefaults().Gift_Transaction_Mirror_Last_Run__c);
	}

	@IsTest
	static void aRunCopiesWaitingGiftsAndRecordsItself() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Gift__c gift = insertGift(100);
			Test.startTest();
			runInline(new GiftTransactionMirrorBatch(null, null));
			Test.stopTest();
			String linked = reread(gift.Id).Gift_Transaction_Id__c;
			Assert.isNotNull(linked, 'The gift is copied (R-GT6).');
			Assert.areEqual(PAID, reread(linked).Status__c, 'With the paid status.');
		}
		List<Error_Log__c> info = logged('Info');
		Assert.areEqual(1, info.size());
		Assert.isTrue(
			info[0].Message__c.startsWith('Gift Transaction mirror run: 1 '),
			info[0].Message__c
		);
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		Assert.isNotNull(settings.Gift_Transaction_Mirror_Last_Run__c, 'The run is recorded.');
		Assert.areEqual(info[0].Message__c, settings.Gift_Transaction_Mirror_Last_Summary__c);
		Assert.areEqual(PAID, settings.Gift_Transaction_Mirror_Status__c, 'Settings are kept.');
	}

	@IsTest
	static void aRunWithAFailedGiftIsNotRecordedSoTheGiftIsReadAgain() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			insertGift(100);
			Test.startTest();
			GiftTransactionMirrorBatch batch = new GiftTransactionMirrorBatch(null, null);
			batch.start(null);
			batch.totals.failed = 1;
			batch.finish(null);
			Test.stopTest();
		}
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		Assert.isNull(
			settings.Gift_Transaction_Mirror_Last_Run__c,
			'The watermark stays, so the failed gift is read again.'
		);
		Assert.areEqual(1, logged('Info').size(), 'The run is still logged.');
	}

	@IsTest
	static void aRunThatIsNotReadyWarnsAndCopiesNothing() {
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		settings.Gift_Transaction_Mirror_Start__c = null;
		update settings;
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Gift__c gift = insertGift(100);
			Test.startTest();
			Id job = GiftTransactionMirrorBatch.runRange(GIFT_DATE, GIFT_DATE);
			Test.stopTest();
			Assert.isNotNull(job);
			Assert.isNull(reread(gift.Id).Gift_Transaction_Id__c);
		}
		List<Error_Log__c> warnings = logged('Warning');
		Assert.areEqual(1, warnings.size(), 'One Warning (R-GT2).');
		Assert.isTrue(warnings[0].Message__c.contains('start date'), warnings[0].Message__c);
	}

	@IsTest
	static void theSummaryCountsDesignations() {
		System.runAs(maria()) {
			GiftTransactionMirrorService.Result totals = new GiftTransactionMirrorService.Result();
			totals.created = 2;
			totals.designated = 3;
			totals.undesignated = 1;
			String summary = GiftTransactionMirrorBatch.summaryOf(totals);
			Assert.isTrue(summary.contains('3 designations written, 1 allocations'), summary);
			totals.designationsUnavailable = true;
			Assert.isTrue(
				GiftTransactionMirrorBatch.summaryOf(totals)
					.endsWith(Label.Mirror_GiftTransactionMirror_DesignationsUnavailable)
			);
			Assert.isTrue(GiftTransactionMirrorBatch.hasHeadroom(100), 'A fresh chunk has room.');
		}
	}

	// ------------------------------------------------------------------ nightly and health

	@IsTest
	static void theNightlyRunIsScheduledOnceListedAndReportedWhenLate() {
		System.runAs(maria()) {
			clearOrgJob();
			GiftTransactionMirrorSchema.useStandIns();
			Test.startTest();
			Id first = GiftTransactionMirrorSchedulable.schedule();
			Id second = GiftTransactionMirrorSchedulable.schedule();
			Assert.areEqual(first, second, 'A second press returns the run already there.');
			ScheduledJobSelector.forget();
			NightlyJobs.forget();
			Assert.isNotNull(GiftTransactionMirrorSchedulable.nextRunAt());
			Assert.isFalse(GiftTransactionMirrorSchedulable.isRunning());
			Assert.isTrue(
				NightlyJobs.isOn(GiftTransactionMirrorSchedulable.step()),
				'In tonight\'s run while the mirror is on.'
			);

			Assert.isFalse(reported(), 'Just scheduled: nothing to say yet.');
			MirrorHealthCheckExtension.nowForTest = System.now().addDays(3);
			Assert.isTrue(reported(), 'Three days without a run is reported.');
			MirrorSettingsWriter.recordGiftTransactionMirrorRun(System.now().addDays(2), 'Ran');
			Assert.isFalse(reported(), 'A run completed a day ago.');

			new GiftTransactionMirrorSchedulable().execute(null);
			GiftTransactionMirrorSchedulable.stop();
			NightlyJobs.forget();
			Assert.isNull(GiftTransactionMirrorSchedulable.scheduledAt(), 'Stopped.');
			Test.stopTest();
		}
	}

	private static Boolean reported() {
		for (HealthCheckService.Finding finding : new MirrorHealthCheckExtension().findings()) {
			if (finding.getKey() == MirrorHealthCheckExtension.GIFT_TRANSACTION_MIRROR_STALE_KEY) {
				return true;
			}
		}
		return false;
	}

	// ---------------------------------------------------------------------- reconciliation

	@IsTest
	static void theReconciliationListsEveryKindOfDifference() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Gift__c same = insertGift(100);
			Gift__c changed = insertGift(50);
			Gift__c notCopied = insertGift(25);
			GiftTransactionMirrorService.copyGifts(new List<Gift__c>{ same, changed });
			changed = reread(changed.Id);
			changed.Amount__c = 60;
			update as user changed;
			Gift__c orphan = GivingTestDataFactory.buildAccountGift(same.Household__c, 10);
			orphan.Status__c = PAID;
			orphan.Gift_Date__c = GIFT_DATE;
			insert as user orphan;

			GiftTransactionMirrorReconciliation.Comparison result = GiftTransactionMirrorReconciliation.compare(
				GIFT_DATE,
				GIFT_DATE
			);
			Assert.areEqual(3, result.giftCount);
			Assert.areEqual(175 + 10, result.giftTotal);
			Assert.areEqual(3, result.giftTransactionCount, 'Two copies and the unlinked one.');
			Assert.areEqual(3, result.differenceCount, String.valueOf(result.differences));
			Map<String, String> reasonByKey = new Map<String, String>();
			for (GiftTransactionMirrorReconciliation.Difference difference : result.differences) {
				reasonByKey.put(difference.key, difference.reason);
			}
			Assert.areEqual(
				Label.Mirror_OpportunityMirror_DiffAmount,
				reasonByKey.get(String.valueOf(changed.Id))
			);
			Assert.areEqual(
				Label.Mirror_GiftTransactionMirror_DiffNoGiftTransaction,
				reasonByKey.get(String.valueOf(notCopied.Id))
			);
			Assert.areEqual(
				Label.Mirror_GiftTransactionMirror_DiffNoGift,
				reasonByKey.get(String.valueOf(orphan.Id))
			);
		}
	}

	@IsTest
	static void theReconciliationRefusesWhatItCannotCompare() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			assertRefused(null, GIFT_DATE, Label.Mirror_OpportunityMirror_ErrorDatesRequired);
			assertRefused(
				GIFT_DATE.addDays(1),
				GIFT_DATE,
				Label.Mirror_OpportunityMirror_ErrorDateOrder
			);
			GiftTransactionMirrorSchema.absentForTest = true;
			assertRefused(GIFT_DATE, GIFT_DATE, Label.Mirror_GiftTransactionMirror_Unavailable);
		}
	}

	private static void assertRefused(Date fromDate, Date toDate, String expected) {
		try {
			GiftTransactionMirrorReconciliation.compare(fromDate, toDate);
			Assert.fail('Expected: ' + expected);
		} catch (GiftTransactionMirrorReconciliation.ReconciliationException refused) {
			Assert.areEqual(expected, refused.getMessage());
		}
	}
}
