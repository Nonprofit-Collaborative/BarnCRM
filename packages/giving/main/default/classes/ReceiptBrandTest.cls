/**
 * Brand-aware receipts (C-47b, R-BR5) and receipt numbering per brand (C-47f, R-BR8): a gift's
 * brand prints its name, legal entity and signature and numbers from its own series; with brands
 * off the receipt is the organization's as before; a new gift takes its appeal's brand (C-47d).
 */
@IsTest(
	testFor='ApexClass:ReceiptService, ApexClass:ReceiptContentBuilder, ApexClass:ReceiptNumberSequence, ApexClass:BrandDefaultHandler, ApexTrigger:GiftTrigger'
)
private class ReceiptBrandTest {
	private static final Date GIFT_DATE = Date.newInstance(2026, 4, 12);

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	private static Brand__c brandsOn(String scope) {
		BarnCRM_Settings__c core = BarnCRM_Settings__c.getOrgDefaults();
		core.Brand_Management__c = true;
		upsert core;
		Giving_Settings__c giving = Giving_Settings__c.getOrgDefaults();
		giving.SetupOwnerId = UserInfo.getOrganizationId();
		giving.Receipt_Numbering_Scope__c = scope;
		upsert giving;
		Legal_Entity__c entity = new Legal_Entity__c(
			Name = 'Barn Thrift LLC',
			Tax_Id__c = '98-7654321'
		);
		insert entity;
		Brand__c thrift = new Brand__c(
			Name = 'Barn Thrift',
			Legal_Entity__c = entity.Id,
			Receipt_Number_Prefix__c = 'BT',
			Letter_Signature__c = 'Ana Ruiz\nStore Manager'
		);
		insert thrift;
		return thrift;
	}

	private static Gift__c gift(Id brandId) {
		Contact donor = GivingTestDataFactory.insertHouseholdContact(
			'The Lin Family',
			'Wei',
			'Lin'
		);
		Gift__c record = ReceiptTestDataFactory.plainCashGift(donor.Id, 75, GIFT_DATE);
		record.Brand__c = brandId;
		insert record;
		return record;
	}

	@IsTest
	static void aBrandedGiftPrintsAndNumbersAsItsBrand() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			ReceiptTestDataFactory.RecordingRenderer renderer = ReceiptTestDataFactory.setUpReceipting();
			Brand__c thrift = brandsOn('Brand');
			Gift__c branded = gift(thrift.Id);

			Test.startTest();
			Receipt__c receipt = ReceiptService.issueForGift(branded.Id);
			Test.stopTest();

			String html = renderer.renderedHtml[renderer.renderedHtml.size() - 1];
			Assert.isTrue(
				receipt.Receipt_Number__c.startsWith('BT-2026-'),
				'The brand series and prefix'
			);
			Assert.isTrue(html.contains('Barn Thrift LLC'), 'The legal entity receipts it');
			Assert.isTrue(html.contains('98-7654321'), 'The entity tax ID');
			Assert.isTrue(html.contains('Store Manager'), 'The brand signature');
		}
	}

	@IsTest
	static void brandsOffKeepTheOrganizationReceipt() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			ReceiptTestDataFactory.RecordingRenderer renderer = ReceiptTestDataFactory.setUpReceipting();
			Brand__c thrift = brandsOn('Brand');
			BarnCRM_Settings__c core = BarnCRM_Settings__c.getOrgDefaults();
			core.Brand_Management__c = false;
			upsert core;
			Gift__c branded = gift(thrift.Id);

			Test.startTest();
			Receipt__c receipt = ReceiptService.issueForGift(branded.Id);
			Test.stopTest();

			String html = renderer.renderedHtml[renderer.renderedHtml.size() - 1];
			Assert.isTrue(receipt.Receipt_Number__c.startsWith('HFH-'), 'The organization series');
			Assert.isFalse(html.contains('Barn Thrift'), 'No brand prints while brands are off');
			Assert.isTrue(html.contains('Hope For Homes'), 'The organization prints');
		}
	}

	@IsTest
	static void aNewGiftTakesItsAppealsBrand() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			ReceiptTestDataFactory.setUpReceipting();
			Brand__c thrift = brandsOn('Organization');
			Appeal__c appeal = new Appeal__c(Name = 'Spring Sale', Brand__c = thrift.Id);
			insert appeal;
			Contact donor = GivingTestDataFactory.insertHouseholdContact(
				'The Ng Family',
				'Kim',
				'Ng'
			);
			List<Gift__c> gifts = new List<Gift__c>();
			for (Integer i = 0; i < 50; i++) {
				Gift__c record = ReceiptTestDataFactory.plainCashGift(donor.Id, 10, GIFT_DATE);
				record.Appeal__c = appeal.Id;
				gifts.add(record);
			}

			Test.startTest();
			insert gifts;
			Test.stopTest();

			Assert.areEqual(
				50,
				[SELECT COUNT() FROM Gift__c WHERE Brand__c = :thrift.Id],
				'Every gift takes the appeal brand'
			);
		}
	}
}
