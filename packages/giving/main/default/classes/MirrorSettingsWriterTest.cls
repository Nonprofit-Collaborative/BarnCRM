/**
 * Mirror saves its last completed run as Giving run state: only the two run keys of the mirror
 * that ran are written, so the other mirror's run and a direction saved meanwhile are never
 * touched (R-OM8, R-GT6).
 */
@IsTest(testFor='ApexClass:MirrorSettingsWriter')
private class MirrorSettingsWriterTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	private static User admin() {
		return TestUsers.adminWith('Giving_Admin');
	}

	@IsTest
	static void recordsTheRunWhenNoneWasRecordedBefore() {
		System.runAs(admin()) {
			Datetime ranAt = Datetime.newInstance(2026, 5, 1, 10, 30, 0);

			Test.startTest();
			MirrorSettingsWriter.recordOpportunityMirrorRun(ranAt, '3 Opportunities created.');
			Test.stopTest();

			Assert.areEqual(ranAt, GivingState.moment(GivingState.OPPORTUNITY_MIRROR_LAST_RUN), 'The run time is saved');
			Assert.areEqual(
				'3 Opportunities created.',
				GivingState.text(GivingState.OPPORTUNITY_MIRROR_SUMMARY),
				'The summary is saved'
			);
			Assert.isNull(
				GivingState.moment(GivingState.GIFT_TRANSACTION_MIRROR_LAST_RUN),
				'The other mirror has no run yet'
			);
		}
	}

	@IsTest
	static void updatesOnlyTheRunKeysOfTheMirrorThatRan() {
		System.runAs(admin()) {
			GivingState.put(new Map<String, Object>{ GivingState.OPPORTUNITY_MIRROR_SUMMARY => 'Kept' });
			Datetime ranAt = Datetime.newInstance(2026, 5, 2, 8, 0, 0);

			Test.startTest();
			MirrorSettingsWriter.recordGiftTransactionMirrorRun(ranAt, '5 gifts copied.');
			Test.stopTest();

			Assert.areEqual(
				ranAt,
				GivingState.moment(GivingState.GIFT_TRANSACTION_MIRROR_LAST_RUN),
				'The Gift Transaction run time is saved'
			);
			Assert.areEqual(
				'5 gifts copied.',
				GivingState.text(GivingState.GIFT_TRANSACTION_MIRROR_SUMMARY),
				'Its summary is saved'
			);
			Assert.areEqual(
				'Kept',
				GivingState.text(GivingState.OPPORTUNITY_MIRROR_SUMMARY),
				'The Opportunity mirror keys are untouched'
			);
		}
	}

	@IsTest
	static void keepsADirectionSavedBeforeTheRun() {
		System.runAs(admin()) {
			ModuleSettings.setForTest('Mirror_Opportunity_Mirror_Direction', OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);

			Test.startTest();
			MirrorSettingsWriter.recordOpportunityMirrorRun(System.now(), 'Done');
			Test.stopTest();

			Assert.areEqual(
				OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES,
				ModuleSettings.text('Mirror_Opportunity_Mirror_Direction'),
				'A direction saved before the run completes is not undone'
			);
		}
	}

	@IsTest
	static void shortensALongSummaryAndAcceptsNone() {
		System.runAs(admin()) {
			Test.startTest();
			MirrorSettingsWriter.recordOpportunityMirrorRun(System.now(), 'x'.repeat(400));
			Integer savedLength = GivingState.text(GivingState.OPPORTUNITY_MIRROR_SUMMARY).length();
			MirrorSettingsWriter.recordOpportunityMirrorRun(System.now(), null);
			Test.stopTest();

			Assert.areEqual(255, savedLength, 'A long summary is cut to 255 characters');
			Assert.isNull(
				GivingState.text(GivingState.OPPORTUNITY_MIRROR_SUMMARY),
				'A run with no summary clears the last one'
			);
		}
	}
}
