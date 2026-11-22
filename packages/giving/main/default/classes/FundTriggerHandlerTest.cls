/**
 * At most one fund is the default, and Maria never has to remember to untick the old one
 * (R-F1). The Default Fund setting decides the flag, and the trigger never saves it (R-F4).
 */
@IsTest(testFor='ApexClass:FundTriggerHandler')
private class FundTriggerHandlerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	@IsTest
	static void markingANewDefaultClearsTheOldOne() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', true);
			insert general;
			Fund__c annual = GivingTestDataFactory.buildFund('Annual Fund', false);
			insert annual;

			Test.startTest();
			annual.Is_Default__c = true;
			update annual;
			Test.stopTest();

			System.assertEquals(
				false,
				[SELECT Is_Default__c FROM Fund__c WHERE Id = :general.Id].Is_Default__c,
				'Only one fund catches undesignated gifts.'
			);
			System.assertEquals(
				true,
				[SELECT Is_Default__c FROM Fund__c WHERE Id = :annual.Id].Is_Default__c,
				'The fund Maria just marked is the default.'
			);
		}
	}

	@IsTest
	static void twoDefaultsInOneSaveAreRefused() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			String message = '';

			Test.startTest();
			try {
				insert new List<Fund__c>{
					GivingTestDataFactory.buildFund('General', true),
					GivingTestDataFactory.buildFund('Building', true)
				};
			} catch (DmlException twoDefaults) {
				message = twoDefaults.getDmlMessage(0);
			}
			Test.stopTest();

			System.assert(
				message.contains('Only one fund can be the default'),
				'Two defaults in one save has no defensible answer: ' + message
			);
		}
	}

	@IsTest
	static void theDefaultFundIsResolvedForGiftEntry() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', true);
			insert general;

			Test.startTest();
			Id resolved = GiftService.resolveDefaultFundId();
			Test.stopTest();

			System.assertEquals(general.Id, resolved, 'The flagged fund is the default fund.');
		}
	}

	@IsTest
	static void withNoFundAtAllThereIsNoDefault() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Test.startTest();
			Id resolved = GiftService.resolveDefaultFundId();
			Test.stopTest();

			System.assertEquals(
				null,
				resolved,
				'A fresh org has no default fund yet, and says so rather than guessing.'
			);
		}
	}

	@IsTest
	static void twoHundredFundsSaveInOneGo() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			List<Fund__c> funds = new List<Fund__c>();
			for (Integer i = 0; i < 200; i++) {
				funds.add(GivingTestDataFactory.buildFund('Fund ' + i, false));
			}

			Test.startTest();
			insert funds;
			Test.stopTest();

			System.assertEquals(200, [SELECT COUNT() FROM Fund__c], 'Two hundred in one save.');
		}
	}

	@IsTest
	static void tickingADefaultNeverSavesTheSetting() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', false);
			insert general;

			Test.startTest();
			general.Is_Default__c = true;
			update general;
			Test.stopTest();

			Assert.isNull(
				ModuleSettings.text('Giving_Default_Fund'),
				'A trigger never saves a setting; the Default Fund setting stays blank (R-F4).'
			);
			Assert.areEqual(
				general.Id,
				GiftService.resolveDefaultFundId(),
				'While the setting is blank, ticking the box changes where gifts land.'
			);
		}
	}

	@IsTest
	static void theSettingDecidesEachFundsFlag() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', true);
			insert general;
			Fund__c building = GivingTestDataFactory.buildFund('Building', false);
			insert building;
			ModuleSettings.setForTest('Giving_Default_Fund', String.valueOf(building.Id));

			Test.startTest();
			update new List<Fund__c>{ new Fund__c(Id = general.Id, Name = 'General'), new Fund__c(Id = building.Id) };
			Test.stopTest();

			Assert.isFalse(
				[SELECT Is_Default__c FROM Fund__c WHERE Id = :general.Id].Is_Default__c,
				'A fund the setting does not name loses the flag on its next save.'
			);
			Assert.isTrue(
				[SELECT Is_Default__c FROM Fund__c WHERE Id = :building.Id].Is_Default__c,
				'The fund the setting names shows the flag.'
			);
			Assert.areEqual(building.Id, GiftService.resolveDefaultFundId(), 'Gifts land where the setting says.');
		}
	}

	@IsTest
	static void aTickThatDisagreesWithTheSettingIsRefused() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', true);
			insert general;
			Fund__c building = GivingTestDataFactory.buildFund('Building', false);
			insert building;
			ModuleSettings.setForTest('Giving_Default_Fund', String.valueOf(general.Id));
			String message = '';

			Test.startTest();
			try {
				building.Is_Default__c = true;
				update building;
			} catch (DmlException refused) {
				message = refused.getDmlMessage(0);
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_Fund_DefaultFromSettings'),
				message,
				'The refusal says the default fund is chosen in BarnCRM Settings.'
			);
			Assert.areEqual(general.Id, GiftService.resolveDefaultFundId(), 'The setting still decides.');
		}
	}

	@IsTest
	static void aFundThatHasGiftsCannotBeDeleted() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.buildFund('General', true);
			insert general;
			Contact person = GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
			insert GivingTestDataFactory.buildGift(person.Id, 75);

			String message = '';
			Test.startTest();
			try {
				delete general;
			} catch (DmlException deleteError) {
				message = deleteError.getDmlMessage(0);
			}
			Test.stopTest();

			System.assert(
				message.contains('Untick Active instead'),
				'R-F2: a fund with history is deactivated, and the message says so: ' + message
			);
		}
	}

	@IsTest
	static void anUnusedFundIsStillDeletable() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c mistake = GivingTestDataFactory.buildFund('Typo Fund', false);
			insert mistake;

			Test.startTest();
			delete mistake;
			Test.stopTest();

			System.assertEquals(
				0,
				[SELECT COUNT() FROM Fund__c],
				'A fund nothing points at is a mistake, not history.'
			);
		}
	}
}
