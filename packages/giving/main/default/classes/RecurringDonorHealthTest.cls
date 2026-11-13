/**
 * Recurring donor health (G-27, canonical model Section 25V): a processor event finds its
 * recurring gift by subscription id or by the donor's email, an ambiguous email matches nothing,
 * each event type changes the gift's health, linking an unmatched event later applies it, and
 * the page lists the gifts at risk, the revenue by frequency and the follow-up task.
 */
@IsTest(
	testFor='ApexClass:RecurringGiftUpkeep, ApexClass:RecurringGiftEventHandler, ApexClass:RecurringHealthController'
)
private class RecurringDonorHealthTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.ensureDefaultFund();
		}
	}

	private static Contact donor(String email) {
		Contact person = TestDataFactory.person(
			new Contact(FirstName = 'Rae', LastName = 'Sustainer', Email = email)
		);
		insert person;
		return person;
	}

	private static Commitment__c recurring(Id donorId, String subscriptionId) {
		Commitment__c gift = new Commitment__c(
			Type__c = 'Recurring',
			Status__c = 'Active',
			Donor_Contact__c = donorId,
			Amount__c = 25,
			Frequency__c = 'Monthly',
			Start_Date__c = Date.today(),
			Processor_Subscription_Id__c = subscriptionId
		);
		insert gift;
		return gift;
	}

	private static Commitment__c health(Id commitmentId) {
		return [
			SELECT Failed_Charges__c, Last_Failed_Charge__c, Card_Expires__c, Processor_Cancelled__c
			FROM Commitment__c
			WHERE Id = :commitmentId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void eventsFindTheirGiftAndChangeItsHealth() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor('rae@example.org');
			Commitment__c gift = recurring(person.Id, 'sub_123');
			Date failedOn = Date.today().addDays(-3);
			Date expires = Date.today().addMonths(1).toStartOfMonth().addDays(-1);

			Test.startTest();
			insert new List<Recurring_Gift_Event__c>{
				new Recurring_Gift_Event__c(
					Event_Type__c = 'Charge Failed',
					Subscription_Id__c = 'SUB_123',
					Event_Date__c = failedOn
				),
				new Recurring_Gift_Event__c(
					Event_Type__c = 'Charge Failed',
					Donor_Email__c = 'RAE@example.org',
					Event_Date__c = failedOn.addDays(-30)
				),
				new Recurring_Gift_Event__c(
					Event_Type__c = 'Card Expiring',
					Subscription_Id__c = 'sub_123',
					Card_Expires__c = expires
				)
			};
			Test.stopTest();

			Commitment__c after = health(gift.Id);
			Assert.areEqual(
				2,
				after.Failed_Charges__c,
				'Both failed charges count, matched by id and by email.'
			);
			Assert.areEqual(
				failedOn,
				after.Last_Failed_Charge__c,
				'The latest failure date is kept, whatever the order.'
			);
			Assert.areEqual(expires, after.Card_Expires__c, 'The expiring card month is recorded.');
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Recurring_Gift_Event__c
					WHERE Commitment__c = :gift.Id AND Match_Status__c = 'Matched'
				],
				'Every event is matched to the gift.'
			);
		}
	}

	@IsTest
	static void aSuccessfulChargeClearsFailuresAndCancellation() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Commitment__c gift = recurring(donor('rae@example.org').Id, 'sub_9');
			insert new Recurring_Gift_Event__c(
				Event_Type__c = 'Cancelled',
				Subscription_Id__c = 'sub_9'
			);
			insert new Recurring_Gift_Event__c(
				Event_Type__c = 'Charge Failed',
				Subscription_Id__c = 'sub_9'
			);
			Assert.areEqual(
				Date.today(),
				health(gift.Id).Processor_Cancelled__c,
				'A cancellation is dated.'
			);

			Test.startTest();
			insert new Recurring_Gift_Event__c(
				Event_Type__c = 'Charge Succeeded',
				Subscription_Id__c = 'sub_9'
			);
			insert new Recurring_Gift_Event__c(
				Event_Type__c = 'Card Updated',
				Subscription_Id__c = 'sub_9'
			);
			Test.stopTest();

			Commitment__c after = health(gift.Id);
			Assert.areEqual(0, after.Failed_Charges__c, 'A successful charge resets the failures.');
			Assert.isNull(
				after.Processor_Cancelled__c,
				'A successful charge clears the cancellation.'
			);
			Assert.isNull(
				after.Card_Expires__c,
				'An updated card with no date leaves nothing expiring.'
			);
		}
	}

	@IsTest
	static void anAmbiguousEmailStaysUnmatchedUntilLinked() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor('two@example.org');
			Commitment__c first = recurring(person.Id, null);
			recurring(person.Id, null);
			Recurring_Gift_Event__c event = new Recurring_Gift_Event__c(
				Event_Type__c = 'Charge Failed',
				Donor_Email__c = 'two@example.org'
			);
			insert event;
			Recurring_Gift_Event__c saved = [
				SELECT Commitment__c, Match_Status__c
				FROM Recurring_Gift_Event__c
				WHERE Id = :event.Id
			];
			Assert.isNull(
				saved.Commitment__c,
				'Two open recurring gifts for one email match neither.'
			);
			Assert.areEqual('Unmatched', saved.Match_Status__c, 'The event waits as Unmatched.');

			Test.startTest();
			update new Recurring_Gift_Event__c(Id = event.Id, Commitment__c = first.Id);
			Test.stopTest();

			Assert.areEqual(1, health(first.Id).Failed_Charges__c, 'Linking the event applies it.');
			Assert.areEqual(
				'Matched',
				[SELECT Match_Status__c FROM Recurring_Gift_Event__c WHERE Id = :event.Id]
				.Match_Status__c,
				'A linked event is Matched.'
			);
		}
	}

	@IsTest
	static void manyEventsInOneSaveApplyTogether() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Commitment__c gift = recurring(donor('bulk@example.org').Id, 'sub_bulk');
			List<Recurring_Gift_Event__c> events = new List<Recurring_Gift_Event__c>();
			for (Integer i = 0; i < 200; i++) {
				events.add(
					new Recurring_Gift_Event__c(
						Event_Type__c = 'Charge Failed',
						Subscription_Id__c = 'sub_bulk',
						Event_Date__c = Date.today().addDays(-i)
					)
				);
			}

			Test.startTest();
			insert events;
			Test.stopTest();

			Assert.areEqual(
				200,
				health(gift.Id).Failed_Charges__c,
				'Every failure in the batch counts once.'
			);
		}
	}

	@IsTest
	static void thePageListsGiftsAtRiskAndRevenue() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Commitment__c failing = recurring(donor('page@example.org').Id, 'sub_page');
			recurring(donor('fine@example.org').Id, 'sub_fine');
			insert new Recurring_Gift_Event__c(
				Event_Type__c = 'Charge Failed',
				Subscription_Id__c = 'sub_page'
			);
			insert new Recurring_Gift_Event__c(
				Event_Type__c = 'Charge Failed',
				Subscription_Id__c = 'sub_unknown'
			);

			Test.startTest();
			RecurringHealthController.HealthPage page = RecurringHealthController.getPage();
			Id taskId = RecurringHealthController.createFollowUp(failing.Id);
			Test.stopTest();

			Assert.areEqual(1, page.rows.size(), 'Only the gift with a failed charge is at risk.');
			Assert.areEqual(failing.Id, page.rows[0].id, 'The failing gift is listed.');
			Assert.areEqual(1, page.rows[0].failedCharges, 'Its failed charge shows.');
			Assert.areEqual(1, page.byFrequency.size(), 'Both gifts are Monthly.');
			Assert.areEqual(50, page.byFrequency[0].total, 'Revenue adds both active gifts.');
			Assert.areEqual(1, page.unmatched, 'The event for an unknown subscription is counted.');
			Assert.areEqual(60, page.expiryDays, 'The expiry window defaults to 60 days.');
			Task followUp = [SELECT WhatId, OwnerId FROM Task WHERE Id = :taskId];
			Assert.areEqual(failing.Id, followUp.WhatId, 'The task is about the gift.');
			Assert.areEqual(
				UserInfo.getUserId(),
				followUp.OwnerId,
				'The task is the person\'s own.'
			);
		}
	}
}
