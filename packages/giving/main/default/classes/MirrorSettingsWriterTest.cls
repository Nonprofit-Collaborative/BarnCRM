/**
 * Mirror saves its last completed run on the protected org-level Giving Settings: created from the
 * field defaults when none exists, and otherwise only the two run keys updated, so a direction
 * saved meanwhile is never undone (R-OM8, R-GT6).
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

	private static Integer orgRecords() {
		Id org = UserInfo.getOrganizationId();
		return [SELECT COUNT() FROM Giving_Settings__c WHERE SetupOwnerId = :org];
	}

	@IsTest
	static void createsTheOrgRecordWhenNoneExists() {
		System.runAs(admin()) {
			Datetime ranAt = Datetime.newInstance(2026, 5, 1, 10, 30, 0);
			delete [SELECT Id FROM Giving_Settings__c WHERE SetupOwnerId = :UserInfo.getOrganizationId()];

			Test.startTest();
			MirrorSettingsWriter.recordOpportunityMirrorRun(ranAt, '3 Opportunities created.');
			Test.stopTest();

			Giving_Settings__c saved = Giving_Settings__c.getOrgDefaults();
			Assert.areEqual(1, orgRecords(), 'One org-level record is created');
			Assert.areEqual(ranAt, saved.Opportunity_Mirror_Last_Run__c, 'The run time is saved');
			Assert.areEqual(
				'3 Opportunities created.',
				saved.Opportunity_Mirror_Last_Summary__c,
				'The summary is saved'
			);
			Assert.isNull(saved.Gift_Transaction_Mirror_Last_Run__c, 'The other mirror has no run yet');
		}
	}

	@IsTest
	static void updatesOnlyTheRunKeysOfAnExistingRecord() {
		System.runAs(admin()) {
			Giving_Settings__c existing = Giving_Settings__c.getOrgDefaults();
			existing.Opportunity_Mirror_Last_Summary__c = 'Kept';
			upsert existing;
			Datetime ranAt = Datetime.newInstance(2026, 5, 2, 8, 0, 0);

			Test.startTest();
			MirrorSettingsWriter.recordGiftTransactionMirrorRun(ranAt, '5 gifts copied.');
			Test.stopTest();

			Giving_Settings__c saved = Giving_Settings__c.getOrgDefaults();
			Assert.areEqual(1, orgRecords(), 'The existing record is updated, not duplicated');
			Assert.areEqual(ranAt, saved.Gift_Transaction_Mirror_Last_Run__c, 'The Gift Transaction run time is saved');
			Assert.areEqual('5 gifts copied.', saved.Gift_Transaction_Mirror_Last_Summary__c, 'Its summary is saved');
			Assert.areEqual(
				'Kept',
				saved.Opportunity_Mirror_Last_Summary__c,
				'The Opportunity mirror keys are untouched'
			);
		}
	}

	@IsTest
	static void keepsAnotherSettingSavedBeforeTheRun() {
		System.runAs(admin()) {
			Giving_Settings__c existing = Giving_Settings__c.getOrgDefaults();
			existing.Opportunity_Mirror_Direction__c = OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES;
			upsert existing;

			Test.startTest();
			MirrorSettingsWriter.recordOpportunityMirrorRun(System.now(), 'Done');
			Test.stopTest();

			Assert.areEqual(
				OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES,
				Giving_Settings__c.getOrgDefaults().Opportunity_Mirror_Direction__c,
				'A direction saved before the run completes is not undone'
			);
		}
	}

	@IsTest
	static void shortensALongSummaryAndAcceptsNone() {
		System.runAs(admin()) {
			Test.startTest();
			MirrorSettingsWriter.recordOpportunityMirrorRun(System.now(), 'x'.repeat(400));
			Giving_Settings__c longSaved = Giving_Settings__c.getOrgDefaults();
			Integer savedLength = longSaved.Opportunity_Mirror_Last_Summary__c.length();
			MirrorSettingsWriter.recordOpportunityMirrorRun(System.now(), null);
			Test.stopTest();

			Assert.areEqual(255, savedLength, 'A long summary is cut to the field length');
			Assert.isNull(
				Giving_Settings__c.getOrgDefaults().Opportunity_Mirror_Last_Summary__c,
				'A run with no summary clears the last one'
			);
		}
	}
}
