/**
 * Edit Funds on the gift page (people-giving-16): a split saved in one transaction, the total
 * checked once on the finished split, and the posting lock and a refused split leaving the
 * gift's funds as they were.
 */
@IsTest(
	testFor='ApexClass:GiftAllocationController, ApexClass:GiftAllocationTriggerHandler, ApexClass:GiftAllocationSelector'
)
private class GiftAllocationControllerTest {
	private static User david() {
		return TestDataFactory.createUser(
			'David',
			new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
		);
	}

	private static User jen() {
		return TestDataFactory.createUser(
			'Jen',
			new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
		);
	}

	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.insertDefaultFund();
			insert new List<Fund__c>{
				GivingTestDataFactory.buildFund('Building Fund', false),
				GivingTestDataFactory.buildFund('Scholarships', false)
			};
		}
	}

	private static Id fundNamed(String name) {
		return [SELECT Id FROM Fund__c WHERE Name = :name LIMIT 1].Id;
	}

	private static Id defaultFund() {
		return [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1].Id;
	}

	private static Gift__c gift(Decimal amount) {
		Contact ana = GivingTestDataFactory.insertHouseholdContact(
			'The Nolan Family',
			'Ana',
			'Nolan'
		);
		Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, amount);
		insert gift;
		return gift;
	}

	private static GiftAllocationController.AllocationInput input(Id fundId, Decimal amount) {
		GiftAllocationController.AllocationInput row = new GiftAllocationController.AllocationInput();
		row.fundId = fundId;
		row.amount = amount;
		return row;
	}

	private static Map<Id, Decimal> amountsByFund(Id giftId) {
		Map<Id, Decimal> amounts = new Map<Id, Decimal>();
		for (Gift_Allocation__c allocation : [
			SELECT Fund__c, Amount__c
			FROM Gift_Allocation__c
			WHERE Gift__c = :giftId
			WITH SYSTEM_MODE
		]) {
			amounts.put(allocation.Fund__c, allocation.Amount__c);
		}
		return amounts;
	}

	@IsTest
	static void showsTheFundsAndOffersEditFunds() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.runAs(david()) {
				Gift__c saved = gift(200);

				GiftAllocationController.AllocationState state = GiftAllocationController.getState(
					saved.Id
				);

				Assert.areEqual(200, state.giftAmount);
				Assert.areEqual(1, state.rows.size(), 'The default allocation');
				Assert.areEqual(defaultFund(), state.rows[0].fundId);
				Assert.isNotNull(state.rows[0].fundName, 'Named for the card');
				Assert.areEqual(100, state.rows[0].percent);
				Assert.isTrue(state.canEdit, 'Staff may change the funds of an open gift');
				Assert.isNull(state.lockedMessage);
			}
		}
	}

	@IsTest
	static void davidSplitsAGiftAcrossTwoFundsWithoutDeleting() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.runAs(david()) {
				Gift__c saved = gift(200);
				Id building = fundNamed('Building Fund');
				Id general = defaultFund();

				Test.startTest();
				GiftAllocationController.AllocationState state = GiftAllocationController.save(
					saved.Id,
					new List<GiftAllocationController.AllocationInput>{
						input(building, 100),
						input(general, 100)
					}
				);
				Test.stopTest();

				Assert.areEqual(2, state.rows.size());
				Map<Id, Decimal> amounts = amountsByFund(saved.Id);
				Assert.areEqual(100, amounts.get(building), 'Half to the building fund');
				Assert.areEqual(100, amounts.get(general), 'Half stays where it was');
			}
		}
	}

	@IsTest
	static void aNewFundTakesOverTheRowOfAFundThatLeft() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.runAs(david()) {
				Gift__c saved = gift(90);
				Id building = fundNamed('Building Fund');
				Id original = [SELECT Id FROM Gift_Allocation__c WHERE Gift__c = :saved.Id].Id;

				GiftAllocationController.save(
					saved.Id,
					new List<GiftAllocationController.AllocationInput>{ input(building, 90) }
				);

				Gift_Allocation__c moved = [
					SELECT Id, Fund__c, Amount__c, Percent__c
					FROM Gift_Allocation__c
					WHERE Gift__c = :saved.Id
					WITH SYSTEM_MODE
				];
				Assert.areEqual(original, moved.Id, 'The row is reused, so nothing is deleted');
				Assert.areEqual(building, moved.Fund__c);
				Assert.areEqual(100, moved.Percent__c);
			}
		}
	}

	@IsTest
	static void jenMergesASplitBackIntoOneFund() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.runAs(jen()) {
				Gift__c saved = gift(300);
				Id building = fundNamed('Building Fund');
				Id scholarships = fundNamed('Scholarships');
				GiftAllocationController.save(
					saved.Id,
					new List<GiftAllocationController.AllocationInput>{
						input(building, 100),
						input(scholarships, 100.5),
						input(defaultFund(), 99.5)
					}
				);

				GiftAllocationController.save(
					saved.Id,
					new List<GiftAllocationController.AllocationInput>{ input(scholarships, 300) }
				);

				Map<Id, Decimal> amounts = amountsByFund(saved.Id);
				Assert.areEqual(1, amounts.size(), 'The other rows are deleted');
				Assert.areEqual(300, amounts.get(scholarships));
			}
		}
	}

	@IsTest
	static void davidRemovesAFundAsGivingStaff() {
		// Plan D-176: Giving Staff may delete Gift Allocations, so staff correct a split alone.
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.runAs(david()) {
				Gift__c saved = gift(100);
				GiftAllocationController.save(
					saved.Id,
					new List<GiftAllocationController.AllocationInput>{
						input(fundNamed('Building Fund'), 50),
						input(defaultFund(), 50)
					}
				);

				GiftAllocationController.save(
					saved.Id,
					new List<GiftAllocationController.AllocationInput>{ input(defaultFund(), 100) }
				);

				Map<Id, Decimal> amounts = amountsByFund(saved.Id);
				Assert.areEqual(1, amounts.size(), 'The building fund row is deleted');
				Assert.areEqual(100, amounts.get(defaultFund()));
			}
		}
	}

	@IsTest
	static void aSplitThatDoesNotAddUpChangesNothing() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.runAs(david()) {
				Gift__c saved = gift(100);
				try {
					GiftAllocationController.save(
						saved.Id,
						new List<GiftAllocationController.AllocationInput>{
							input(fundNamed('Building Fund'), 60),
							input(defaultFund(), 30)
						}
					);
					Assert.fail('Ten is left over');
				} catch (AuraHandledException refused) {
					Assert.isTrue(refused.getMessage().contains('10'), refused.getMessage());
				}
				Map<Id, Decimal> amounts = amountsByFund(saved.Id);
				Assert.areEqual(1, amounts.size(), 'Nothing was saved');
				Assert.areEqual(100, amounts.get(defaultFund()));
				Assert.isFalse(GiftService.deferAllocationTotalCheck, 'The check is back on');
			}
		}
	}

	@IsTest
	static void refusesARowWithNoFundOrTheSameFundTwice() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.runAs(david()) {
				Gift__c saved = gift(100);
				Id general = defaultFund();
				List<List<GiftAllocationController.AllocationInput>> splits = new List<List<GiftAllocationController.AllocationInput>>{
					new List<GiftAllocationController.AllocationInput>{ input(null, 100) },
					new List<GiftAllocationController.AllocationInput>{
						input(general, 50),
						input(general, 50)
					},
					new List<GiftAllocationController.AllocationInput>{ input(general, 0) },
					new List<GiftAllocationController.AllocationInput>()
				};
				List<String> expected = new List<String>{
					BarnHelp.text('Giving', 'Giving_FundSplit_NeedsFund'),
					BarnHelp.text('Giving', 'Giving_FundSplit_DuplicateFund'),
					BarnHelp.text('Giving', 'Giving_FundSplit_NeedsAmount'),
					BarnHelp.text('Giving', 'Giving_FundSplit_NeedsFund')
				};
				for (Integer index = 0; index < splits.size(); index++) {
					try {
						GiftAllocationController.save(saved.Id, splits[index]);
						Assert.fail('Split ' + index + ' is incomplete');
					} catch (AuraHandledException refused) {
						Assert.areEqual(expected[index], refused.getMessage());
					}
				}
			}
		}
	}

	@IsTest
	static void aPostedGiftKeepsItsFunds() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.runAs(jen()) {
				Gift__c saved = gift(250);
				GiftPostingService.markPosted(new Set<Id>{ saved.Id });

				GiftAllocationController.AllocationState state = GiftAllocationController.getState(
					saved.Id
				);
				Assert.isFalse(state.canEdit, 'Posted');
				Assert.areEqual(Label.Giving_Posting_AllocationLocked, state.lockedMessage);

				try {
					GiftAllocationController.save(
						saved.Id,
						new List<GiftAllocationController.AllocationInput>{
							input(fundNamed('Building Fund'), 250)
						}
					);
					Assert.fail('The lock refuses it');
				} catch (AuraHandledException refused) {
					Assert.areEqual(Label.Giving_Posting_AllocationLocked, refused.getMessage());
				}
				Assert.areEqual(250, amountsByFund(saved.Id).get(defaultFund()), 'Unchanged');
			}
		}
	}

	@IsTest
	static void aGiftNobodyCanSeeIsNotFound() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			try {
				GiftAllocationController.getState(null);
				Assert.fail('No gift');
			} catch (AuraHandledException refused) {
				Assert.areEqual(Label.Giving_Gift_OriginalNotFound, refused.getMessage());
			}
		}
	}
}
