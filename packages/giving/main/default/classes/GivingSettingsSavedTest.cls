/**
 * Changing Default Fund in BarnCRM Settings moves each fund's Is Default at once (R-F4), through
 * Core's `SettingsSavedExtension` seam; other saves leave the funds alone.
 */
@IsTest(testFor='ApexClass:GivingSettingsSaved')
private class GivingSettingsSavedTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	@IsTest
	static void aNewDefaultFundMovesTheFlagAtOnce() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', true);
			insert general;
			Fund__c building = GivingTestDataFactory.buildFund('Building', false);
			insert building;
			ModuleSettings.setForTest('Giving_Default_Fund', String.valueOf(building.Id));

			Test.startTest();
			new GivingSettingsSaved().afterSettingsSaved('Giving_Settings__c', new Set<String>{ 'Default_Fund__c' });
			Test.stopTest();

			Assert.isFalse(
				[SELECT Is_Default__c FROM Fund__c WHERE Id = :general.Id].Is_Default__c,
				'The old default loses the flag.'
			);
			Assert.isTrue(
				[SELECT Is_Default__c FROM Fund__c WHERE Id = :building.Id].Is_Default__c,
				'The chosen fund shows the flag.'
			);
		}
	}

	@IsTest
	static void otherSavesLeaveTheFundsAlone() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', true);
			insert general;
			Fund__c building = GivingTestDataFactory.buildFund('Building', false);
			insert building;
			ModuleSettings.setForTest('Giving_Default_Fund', String.valueOf(building.Id));

			Test.startTest();
			new GivingSettingsSaved()
				.afterSettingsSaved('Giving_Settings__c', new Set<String>{ 'Receipt_Statement_Year__c' });
			new GivingSettingsSaved().afterSettingsSaved('BarnCRM_Settings__c', new Set<String>{ 'Default_Fund__c' });
			Test.stopTest();

			Assert.isTrue(
				[SELECT Is_Default__c FROM Fund__c WHERE Id = :general.Id].Is_Default__c,
				'No Default Fund change, no fund saved.'
			);
		}
	}

	@IsTest
	static void aBlankSettingChangesNothing() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', true);
			insert general;
			ModuleSettings.setForTest('Giving_Default_Fund', null);

			Test.startTest();
			GivingSettingsSaved.syncDefaultFlags();
			Test.stopTest();

			Assert.isTrue(
				[SELECT Is_Default__c FROM Fund__c WHERE Id = :general.Id].Is_Default__c,
				'While the setting is blank, the ticked fund stays the default.'
			);
		}
	}
}
