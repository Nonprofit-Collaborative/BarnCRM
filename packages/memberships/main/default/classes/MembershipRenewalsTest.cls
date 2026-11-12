/**
 * The nightly membership run (canonical model R-MEM4 to R-MEM6): gifts to a level's fund join,
 * renew or activate members once each; ended terms move to Grace, then Lapsed, unless a recurring
 * gift is still active; reminders go once per term end. Giving is read through test overrides.
 */
@IsTest(
	testFor='ApexClass:MembershipRenewals, ApexClass:MembershipEmails, ApexClass:MembershipsSettings, ApexClass:MembershipsNightlyJobProvider'
)
private class MembershipRenewalsTest {
	private static final String ADMIN = 'Memberships_Admin';
	private static final String FUND = 'a0F000000000001';
	private static final Date TODAY = Date.newInstance(2026, 6, 1);

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN);
	}

	private static Id fakeId(Integer n) {
		return Id.valueOf(
			Membership_Benefit__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
				.getKeyPrefix() + String.valueOf(n).leftPad(12, '0')
		);
	}

	private static Map<String, Membership_Level__c> levels() {
		Map<String, Membership_Level__c> byName = new Map<String, Membership_Level__c>{
			'Individual' => new Membership_Level__c(
				Name = 'Individual',
				Dues__c = 50,
				Term_Months__c = 12,
				Grace_Days__c = 30,
				Fund_Id__c = FUND
			),
			'Family' => new Membership_Level__c(
				Name = 'Family',
				Dues__c = 90,
				Term_Months__c = 12,
				Grace_Days__c = 30,
				Fund_Id__c = FUND
			)
		};
		insert as user byName.values();
		return byName;
	}

	private static Contact person(String name) {
		Contact person = new Contact(
			LastName = name,
			Email = name.deleteWhitespace() + '@example.org'
		);
		insert as user person;
		return person;
	}

	private static MembershipRenewals.GiftRow gift(Integer n, Id contactId, Decimal amount) {
		MembershipRenewals.GiftRow row = new MembershipRenewals.GiftRow();
		row.giftId = fakeId(n);
		row.contactId = contactId;
		row.amount = amount;
		row.fundId = FUND + 'AAA';
		row.giftDate = TODAY.addDays(-3);
		return row;
	}

	private static List<Membership_Term__c> termsOf(Id contactId) {
		return [
			SELECT
				Id,
				Status__c,
				Level__r.Name,
				Source__c,
				Start_Date__c,
				Gift_Id__c,
				Origin__c,
				Reminded_For__c
			FROM Membership_Term__c
			WHERE Contact__c = :contactId
			WITH USER_MODE
			ORDER BY CreatedDate, Start_Date__c NULLS FIRST
		];
	}

	@IsTest
	static void giftsJoinRenewAndActivateMembersOnceEach() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = TODAY;
			Map<String, Membership_Level__c> byName = levels();
			Contact newcomer = person('Zzmem Newcomer');
			Contact renewer = person('Zzmem Renewer');
			Contact waiting = person('Zzmem Waiting');
			insert as user new List<Membership_Term__c>{
				new Membership_Term__c(
					Level__c = byName.get('Individual').Id,
					Contact__c = renewer.Id,
					Status__c = 'Current',
					Start_Date__c = TODAY.addMonths(-11)
				),
				new Membership_Term__c(
					Level__c = byName.get('Individual').Id,
					Contact__c = waiting.Id,
					Status__c = 'Pending'
				)
			};
			MembershipRenewals.giftsOverride = new List<MembershipRenewals.GiftRow>{
				gift(1, newcomer.Id, 95),
				gift(2, renewer.Id, 50),
				gift(3, waiting.Id, 60),
				gift(4, person('Zzmem Small').Id, 10)
			};
			Assert.areEqual(3, MembershipRenewals.renewFromGifts(), 'three members paid');
			Assert.areEqual(0, MembershipRenewals.renewFromGifts(), 'a gift pays only once');

			List<Membership_Term__c> joined = termsOf(newcomer.Id);
			Assert.areEqual(1, joined.size(), 'the newcomer joined');
			Assert.areEqual(
				'Family',
				joined[0].Level__r.Name,
				'at the highest level the gift meets'
			);
			Assert.areEqual('Gift', joined[0].Source__c, 'paid by a gift');

			List<Membership_Term__c> renewed = termsOf(renewer.Id);
			Assert.areEqual(2, renewed.size(), 'a new term for the renewer');
			Assert.areEqual('Renewed', renewed[0].Status__c, 'the old term closed');
			Assert.areEqual('Renewal', renewed[1].Origin__c, 'continues the membership');

			List<Membership_Term__c> activated = termsOf(waiting.Id);
			Assert.areEqual(1, activated.size(), 'the pending term itself is used');
			Assert.areEqual('Current', activated[0].Status__c, 'and is current');
			Assert.areEqual(TODAY.addDays(-3), activated[0].Start_Date__c, 'from the gift date');
		}
	}

	@IsTest
	static void endedTermsMoveToGraceThenLapsedUnlessARecurringGiftIsActive() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = TODAY;
			Id level = levels().get('Individual').Id;
			Contact inGrace = person('Zzmem Grace');
			Contact gone = person('Zzmem Gone');
			Contact monthly = person('Zzmem Monthly');
			String commitment = String.valueOf(fakeId(9));
			insert as user new List<Membership_Term__c>{
				new Membership_Term__c(
					Level__c = level,
					Contact__c = inGrace.Id,
					Status__c = 'Current',
					Start_Date__c = TODAY.addYears(-1).addDays(-10)
				),
				new Membership_Term__c(
					Level__c = level,
					Contact__c = gone.Id,
					Status__c = 'Current',
					Start_Date__c = TODAY.addYears(-1).addDays(-60)
				),
				new Membership_Term__c(
					Level__c = level,
					Contact__c = monthly.Id,
					Status__c = 'Current',
					Start_Date__c = TODAY.addYears(-1).addDays(-5),
					Commitment_Id__c = commitment
				)
			};
			MembershipRenewals.activeCommitmentsOverride = new Set<String>{ commitment.left(15) };
			Assert.areEqual(3, MembershipRenewals.lapse(), 'every ended term moved');
			Assert.areEqual('Grace', termsOf(inGrace.Id)[0].Status__c, 'within the grace days');
			Assert.areEqual('Lapsed', termsOf(gone.Id)[0].Status__c, 'past the grace days');
			List<Membership_Term__c> renewed = termsOf(monthly.Id);
			Assert.areEqual(2, renewed.size(), 'the recurring gift renewed it');
			Assert.areEqual('Recurring Gift', renewed[1].Source__c, 'paid by the recurring gift');
		}
	}

	@IsTest
	static void graceTermsAreLapsedOnlyOncePastTheirGraceDays() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = TODAY;
			Id level = levels().get('Individual').Id;
			Contact stillIn = person('Zzmem Still');
			Contact pastIt = person('Zzmem Past');
			insert as user new List<Membership_Term__c>{
				new Membership_Term__c(
					Level__c = level,
					Contact__c = stillIn.Id,
					Status__c = 'Grace',
					Start_Date__c = TODAY.addYears(-1).addDays(-10)
				),
				new Membership_Term__c(
					Level__c = level,
					Contact__c = pastIt.Id,
					Status__c = 'Grace',
					Start_Date__c = TODAY.addYears(-1).addDays(-60)
				)
			};
			Assert.areEqual(1, MembershipRenewals.lapse(), 'only the term past its grace moved');
			Assert.areEqual('Grace', termsOf(stillIn.Id)[0].Status__c, 'within the grace days');
			Assert.areEqual('Lapsed', termsOf(pastIt.Id)[0].Status__c, 'past the grace days');
		}
	}

	@IsTest
	static void remindersGoOncePerTermEndAndASendFailureIsRetried() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = TODAY;
			Id level = levels().get('Individual').Id;
			Contact member = person('Zzmem Remind');
			insert as user new Membership_Term__c(
				Level__c = level,
				Contact__c = member.Id,
				Status__c = 'Current',
				Start_Date__c = TODAY.addYears(-1).addDays(10)
			);
			RecordingEmailSender failing = new RecordingEmailSender();
			failing.failAll = true;
			MembershipRenewals.emailSender = failing;
			Assert.areEqual(0, MembershipRenewals.remind(), 'the send failed');
			RecordingEmailSender sender = new RecordingEmailSender();
			MembershipRenewals.emailSender = sender;
			Assert.areEqual(1, MembershipRenewals.remind(), 'retried the next night');
			Assert.areEqual(0, MembershipRenewals.remind(), 'and not sent twice');
			Assert.areEqual(member.Id, sender.received[0].getTargetObjectId(), 'to the member');
		}
	}

	@IsTest
	static void aRefusedSendUnstampsEveryReminderSoItIsRetried() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = TODAY;
			Id level = levels().get('Individual').Id;
			Contact member = person('Zzmem Refused');
			insert as user new Membership_Term__c(
				Level__c = level,
				Contact__c = member.Id,
				Status__c = 'Current',
				Start_Date__c = TODAY.addYears(-1).addDays(10)
			);
			RecordingEmailSender refusing = new RecordingEmailSender();
			refusing.refuseWith = 'Single email limit exceeded.';
			MembershipRenewals.emailSender = refusing;
			Assert.areEqual(0, MembershipRenewals.remind(), 'the whole send was refused');
			Assert.isNull(termsOf(member.Id)[0].Reminded_For__c, 'the stamp was cleared');
			MembershipRenewals.emailSender = new RecordingEmailSender();
			Assert.areEqual(1, MembershipRenewals.remind(), 'retried the next night');
		}
	}

	@IsTest
	static void theNightlyStepRunsEveryPhase() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			NightlyStep step = new MembershipsNightlyJobProvider().nightlySteps()[0];
			Assert.areEqual(MembershipRenewals.JOB_NAME, step.key, 'the Memberships step');
			MembershipRenewals.giftsOverride = new List<MembershipRenewals.GiftRow>();
			Assert.isFalse(MembershipsSettings.remindersEnabled(), 'reminders ship off');
			Assert.isTrue(MembershipsSettings.renewFromGifts(), 'gift renewals ship on');
			Assert.areEqual(30, MembershipsSettings.reminderDays(), 'thirty days ahead');
			MembershipRenewals.run();
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Membership_Term__c WITH USER_MODE],
				'nothing to do on an empty org'
			);
		}
	}
}
