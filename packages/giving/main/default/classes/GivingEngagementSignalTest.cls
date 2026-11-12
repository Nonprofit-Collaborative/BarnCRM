/**
 * The Gifts part of the engagement score counts each donor's Received gifts in the window
 * (C-64, canonical model R-ES2), and Core finds it by name.
 */
@IsTest(testFor='ApexClass:GivingEngagementSignal')
private class GivingEngagementSignalTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			TestDataFactory.defaultSettings();
			GivingTestDataFactory.insertDefaultFund();
			insert new List<Contact>{
				new Contact(FirstName = 'Ana', LastName = 'Nolan'),
				new Contact(FirstName = 'Wei', LastName = 'Lee')
			};
		}
	}

	@IsTest
	static void sumsReceivedGiftsInTheWindowOnly() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact ana = [SELECT Id FROM Contact WHERE FirstName = 'Ana'];
			Contact wei = [SELECT Id FROM Contact WHERE FirstName = 'Wei'];
			List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana.Id, 3, 100);
			gifts[0].Gift_Date__c = Date.today().addDays(-10);
			gifts[1].Gift_Date__c = Date.today().addMonths(-13);
			gifts[2].Gift_Date__c = Date.today().addDays(-5);
			gifts[2].Status__c = 'Pending';
			Gift__c weiGift = GivingTestDataFactory.buildGift(wei.Id, 250);
			weiGift.Gift_Date__c = Date.today();
			gifts.add(weiGift);
			insert gifts;

			Test.startTest();
			EngagementSignalExtension signal = (EngagementSignalExtension) NamespaceUtil.resolveType(
					'GivingEngagementSignal'
				)
				.newInstance();
			Map<Id, Decimal> totals = signal.totals(
				new Set<Id>{ ana.Id, wei.Id },
				Date.today().addMonths(-12)
			);
			Test.stopTest();

			Assert.areEqual('Gifts', signal.key(), 'The Gifts part');
			Assert.areEqual(100, totals.get(ana.Id), 'Only the Received gift in the window counts');
			Assert.areEqual(250, totals.get(wei.Id), 'Each donor has their own total');
		}
	}
}
