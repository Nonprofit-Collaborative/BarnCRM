/**
 * Payments subscriptions in Giving (PAY-04, R-RH5; ADR-NEXT payments subscriptions, decision 4):
 * the listener fills a recurring gift's processor ids once and records each change once as a
 * Recurring Gift Event, which G-27's rules apply to the gift's health.
 */
@IsTest(testFor='ApexClass:GivingDonations, ApexClass:RecurringGiftUpkeep')
private class GivingSubscriptionsTest {
	@TestSetup
	static void makeData() {
		TestUsers.adminWith('Giving_Admin');
	}

	private static User admin() {
		return TestUsers.adminWith('Giving_Admin');
	}

	private static List<Commitment__c> recurring(Integer count) {
		List<Contact> people = new List<Contact>();
		for (Integer i = 0; i < count; i++) {
			people.add(new Contact(FirstName = 'Sam', LastName = 'Zzsub' + i));
		}
		insert as user people;
		List<Commitment__c> gifts = new List<Commitment__c>();
		for (Contact person : people) {
			gifts.add(
				new Commitment__c(
					Type__c = 'Recurring',
					Status__c = 'Active',
					Donor_Contact__c = person.Id,
					Amount__c = 20,
					Frequency__c = 'Monthly',
					Start_Date__c = Date.today()
				)
			);
		}
		insert as user gifts;
		return gifts;
	}

	private static Map<String, Object> change(Id source, String event, String key) {
		return new Map<String, Object>{
			'subscriptionId' => 'sub_' + source,
			'customerId' => 'cus_' + source,
			'sourceRecordId' => source,
			'event' => event,
			'eventKey' => key,
			'eventDate' => Date.today(),
			'cardExpires' => event == 'cardUpdated' ? Date.newInstance(2034, 12, 31) : null,
			'detail' => 'From the processor'
		};
	}

	private static Object tell(List<Map<String, Object>> changes) {
		return new GivingDonations()
			.call('subscriptionsChanged', new Map<String, Object>{ 'changes' => changes });
	}

	@IsTest
	static void fillsTheIdsAndRecordsEachChangeOnce() {
		System.runAs(admin()) {
			Commitment__c gift = recurring(1)[0];
			List<Map<String, Object>> changes = new List<Map<String, Object>>{
				change(gift.Id, 'chargeFailed', 'stripe:evt_1'),
				change(gift.Id, 'cardUpdated', 'stripe:evt_2')
			};

			Test.startTest();
			Object answer = tell(changes);
			tell(changes);
			Test.stopTest();

			Assert.areEqual(true, answer, 'the bulk form is handled');
			Commitment__c after = [
				SELECT
					Processor_Subscription_Id__c,
					Processor_Customer_Id__c,
					Failed_Charges__c,
					Card_Expires__c
				FROM Commitment__c
				WHERE Id = :gift.Id
			];
			Assert.areEqual('sub_' + gift.Id, after.Processor_Subscription_Id__c);
			Assert.areEqual('cus_' + gift.Id, after.Processor_Customer_Id__c);
			Assert.areEqual(1, after.Failed_Charges__c, 'a repeated change counts once');
			Assert.areEqual(Date.newInstance(2034, 12, 31), after.Card_Expires__c);
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Recurring_Gift_Event__c WHERE Commitment__c = :gift.Id],
				'one event per processor event'
			);
		}
	}

	@IsTest
	static void keepsIdsAlreadySetAndIgnoresUnknownNews() {
		System.runAs(admin()) {
			Commitment__c gift = recurring(1)[0];
			gift.Processor_Subscription_Id__c = 'sub_kept';
			update as user gift;
			Map<String, Object> unknown = change(gift.Id, 'somethingElse', 'stripe:evt_9');

			Test.startTest();
			tell(new List<Map<String, Object>>{ unknown, change(null, 'cancelled', 'stripe:x') });
			Test.stopTest();

			Commitment__c after = [
				SELECT Processor_Subscription_Id__c, Processor_Customer_Id__c
				FROM Commitment__c
				WHERE Id = :gift.Id
			];
			Assert.areEqual('sub_kept', after.Processor_Subscription_Id__c);
			Assert.areEqual('cus_' + gift.Id, after.Processor_Customer_Id__c);
			Assert.areEqual(0, [SELECT COUNT() FROM Recurring_Gift_Event__c]);
		}
	}

	@IsTest
	static void aRunOfManyChangesIsOneWrite() {
		System.runAs(admin()) {
			List<Commitment__c> gifts = recurring(41);
			List<Map<String, Object>> changes = new List<Map<String, Object>>();
			for (Integer i = 1; i < gifts.size(); i++) {
				changes.add(change(gifts[i].Id, 'chargeSucceeded', 'paypal:WH-' + i));
			}

			Test.startTest();
			tell(
				new List<Map<String, Object>>{
					change(gifts[0].Id, 'chargeSucceeded', 'paypal:WH-0')
				}
			);
			Integer oneDml = Limits.getDmlStatements();
			Integer oneQueries = Limits.getQueries();
			tell(changes);
			Integer manyDml = Limits.getDmlStatements() - oneDml;
			Integer manyQueries = Limits.getQueries() - oneQueries;
			Test.stopTest();

			// Other modules' Commitment handlers add a fixed cost per run, so the check is that
			// forty changes cost what one does, not an absolute ceiling.
			Assert.isTrue(
				manyDml <= oneDml + 2 && manyQueries <= oneQueries + 2,
				'not one write per change: dml ' +
					manyDml +
					' vs ' +
					oneDml +
					', queries ' +
					manyQueries +
					' vs ' +
					oneQueries
			);
			Assert.areEqual(
				41,
				[
					SELECT COUNT()
					FROM Recurring_Gift_Event__c
					WHERE Event_Type__c = 'Charge Succeeded' AND Match_Status__c = 'Matched'
				]
			);
		}
	}
}
