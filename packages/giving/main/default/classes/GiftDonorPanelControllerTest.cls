/**
 * The Quick Gift Entry donor panel (G-33), as David sees it at the gift table: Ana Nolan's
 * household, her last gifts newest first, and her open pledge with the next payment owed.
 */
@IsTest(testFor='ApexClass:GiftDonorPanelController')
private class GiftDonorPanelControllerTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.insertDefaultFund();
			GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
		}
	}

	private static Contact ana() {
		return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
	}

	@IsTest
	static void aPersonShowsHouseholdRecentGiftsAndOpenPledges() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = ana();
			List<Gift__c> gifts = new List<Gift__c>();
			for (Integer daysAgo : new List<Integer>{ 40, 30, 20, 10 }) {
				Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 100 + daysAgo);
				gift.Gift_Date__c = Date.today().addDays(-daysAgo);
				gifts.add(gift);
			}
			insert gifts;
			insert new List<Commitment__c>{
				new Commitment__c(
					Type__c = 'Pledge',
					Status__c = 'Active',
					Donor_Contact__c = person.Id,
					Amount__c = 100,
					Frequency__c = 'Monthly',
					Start_Date__c = Date.today().addDays(5),
					Expected_Total__c = 1200,
					Installments_Planned__c = 12
				),
				new Commitment__c(
					Type__c = 'Recurring',
					Status__c = 'Cancelled',
					Donor_Contact__c = person.Id,
					Amount__c = 25,
					Frequency__c = 'Monthly',
					Start_Date__c = Date.today().addMonths(-6)
				)
			};

			Test.startTest();
			GiftDonorPanelController.Panel panel = GiftDonorPanelController.getPanel(person.Id);
			Test.stopTest();

			Assert.areEqual(person.AccountId, panel.householdId, 'Her household.');
			Assert.areEqual('The Nolan Family', panel.householdName, 'By name.');
			Assert.areEqual(
				GiftDonorPanelController.ROWS,
				panel.gifts.size(),
				'Only the last three gifts.'
			);
			Assert.areEqual(110, panel.gifts[0].amount, 'Newest first: ten days ago.');
			Assert.areEqual(130, panel.gifts[2].amount, 'Then twenty and thirty days ago.');
			Assert.areEqual(1, panel.commitments.size(), 'The cancelled gift is not open.');
			GiftDonorPanelController.CommitmentRow pledge = panel.commitments[0];
			Assert.areEqual('Pledge', pledge.type, 'The open pledge.');
			Assert.areEqual(Date.today().addDays(5), pledge.nextDueDate, 'Its first payment.');
			Assert.areEqual(100, pledge.nextDueAmount, 'Owed in full.');
		}
	}

	@IsTest
	static void anOrganizationHasNoHouseholdAndAnUnknownIdHasNoPanel() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Account organization = GivingTestDataFactory.insertOrganization('Riverside Foundation');
			insert GivingTestDataFactory.buildAccountGift(organization.Id, 500);

			GiftDonorPanelController.Panel panel = GiftDonorPanelController.getPanel(
				organization.Id
			);

			Assert.isNull(panel.householdId, 'An organization is no household member.');
			Assert.areEqual(1, panel.gifts.size(), 'Its gift.');
			Assert.areEqual(500, panel.gifts[0].amount, 'For 500.');
			Assert.isTrue(panel.commitments.isEmpty(), 'Nothing open.');
			Assert.isNull(GiftDonorPanelController.getPanel('not an id'), 'No panel.');
			Assert.isNull(GiftDonorPanelController.getPanel(UserInfo.getUserId()), 'Nor a user.');
			Assert.isNull(GiftDonorPanelController.getPanel(null), 'Nor nothing.');
		}
	}

	/**
	 * QA review Q1: the panel as a gift officer sees it, not an admin. A Standard User holding
	 * BarnCRM Staff and Giving Staff adds a person and a gift, as at the gift table, and the
	 * panel shows that gift. Gifts are private, so the officer's own records are used.
	 */
	@IsTest
	static void aGiftOfficerSeesTheirDonorsGift() {
		User officer;
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			officer = TestDataFactory.createUser(
				'Officer',
				new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
			);
		}
		GiftDonorPanelController.Panel panel;
		Test.startTest();
		System.runAs(officer) {
			Contact donor = TestDataFactory.person(
				new Contact(FirstName = 'Rosa', LastName = 'Park')
			);
			insert donor;
			insert GivingTestDataFactory.buildGift(donor.Id, 75);
			panel = GiftDonorPanelController.getPanel(donor.Id);
		}
		Test.stopTest();

		Assert.areEqual(1, panel.gifts.size(), 'The officer sees the gift just entered.');
		Assert.areEqual(75, panel.gifts[0].amount, 'For 75.');
	}
}
