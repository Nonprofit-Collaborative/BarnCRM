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
		Contact person = TestDataFactory.person(
			new Contact(LastName = name, Email = name.deleteWhitespace() + '@example.org')
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

	@IsTest
	static void theScheduledJobRunsTheSamePhasesAndOnePhaseFailingIsLoggedNotFatal() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = TODAY;
			levels();
			// A gift row with no fund makes the gift phase fail; the others still run.
			MembershipRenewals.GiftRow broken = new MembershipRenewals.GiftRow();
			broken.giftId = fakeId(77);
			broken.amount = 500;
			MembershipRenewals.giftsOverride = new List<MembershipRenewals.GiftRow>{ broken };

			Test.startTest();
			new MembershipRenewals().execute(null);
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c LIKE 'MembershipRenewals.gifts%'
					WITH SYSTEM_MODE
				],
				'The gift phase failure is logged against its phase'
			);
		}
	}

	@IsTest
	static void remindersWithNoTemplateLogAWarningAndSendNothing() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = TODAY;
			Memberships_Settings__c settings = Memberships_Settings__c.getOrgDefaults();
			settings.SetupOwnerId = UserInfo.getOrganizationId();
			settings.Reminder_Template__c = 'No_Such_Membership_Template';
			upsert settings;
			RecordingEmailSender sender = new RecordingEmailSender();
			MembershipRenewals.emailSender = sender;

			Test.startTest();
			Assert.areEqual(0, MembershipRenewals.remind(), 'Nothing to send with');
			Test.stopTest();

			Assert.isTrue(sender.received.isEmpty(), 'No email went out');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'MembershipRenewals' AND Severity__c = 'Warning'
					WITH SYSTEM_MODE
				],
				'The missing template is logged'
			);
		}
	}

	/** One record of a Giving object, made by name since Memberships does not depend on Giving. */
	private static SObject made(String objectName, Map<String, Object> values) {
		SObject record = NamespaceUtil.objectType(objectName).newSObject();
		for (String field : values.keySet()) {
			record.put(field, values.get(field));
		}
		insert record;
		return record;
	}

	private static SObject giftFor(Id fundId, Id contactId, Decimal amount, Id commitmentId) {
		Map<String, Object> values = new Map<String, Object>{
			'Donor_Contact__c' => contactId,
			'Amount__c' => amount,
			'Type__c' => 'Check',
			'Status__c' => 'Received',
			'Gift_Date__c' => TODAY.addDays(-3),
			'Acknowledgment_Status__c' => 'To acknowledge'
		};
		if (commitmentId != null) {
			values.put('Commitment__c', commitmentId);
		}
		SObject gift = made('Gift__c', values);
		// Giving may already have allocated the gift to the default fund.
		if (
			Database.countQuery(
				'SELECT COUNT() FROM Gift_Allocation__c WHERE Gift__c = \'' + gift.Id + '\''
			) == 0
		) {
			made(
				'Gift_Allocation__c',
				new Map<String, Object>{
					'Gift__c' => gift.Id,
					'Fund__c' => fundId,
					'Amount__c' => amount
				}
			);
		}
		return gift;
	}

	@IsTest
	static void giftsReadFromGivingJoinAMemberAndARecurringGiftCountsForTheYear() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			if (
				NamespaceUtil.objectType('Gift_Allocation__c') == null ||
				NamespaceUtil.objectType('Commitment__c') == null
			) {
				return;
			}
			MembershipService.todayOverride = TODAY;
			SObject fund = made(
				'Fund__c',
				new Map<String, Object>{
					'Name' => 'Zzmem Dues',
					'Active__c' => true,
					'Is_Default__c' => true
				}
			);
			insert as user new Membership_Level__c(
				Name = 'Individual',
				Dues__c = 50,
				Term_Months__c = 12,
				Grace_Days__c = 30,
				Fund_Id__c = String.valueOf(fund.Id)
			);
			Contact oneOff = person('Zzmem Oneoff');
			Contact monthly = person('Zzmem Monthlygift');
			SObject commitment = made(
				'Commitment__c',
				new Map<String, Object>{
					'Type__c' => 'Recurring',
					'Status__c' => 'Active',
					'Donor_Contact__c' => monthly.Id,
					'Amount__c' => 20,
					'Frequency__c' => 'Monthly',
					'Start_Date__c' => TODAY.addMonths(-3)
				}
			);
			SObject first = giftFor(fund.Id, oneOff.Id, 60, null);
			// 20 a month is under the dues as a gift, 240 as a year: the year is what counts.
			SObject second = giftFor(fund.Id, monthly.Id, 20, commitment.Id);

			Assert.areEqual(2, MembershipRenewals.renewFromGifts(), 'both members joined');

			List<Membership_Term__c> single = termsOf(oneOff.Id);
			Assert.areEqual(1, single.size(), 'the one-off giver joined');
			Assert.areEqual('Gift', single[0].Source__c, 'paid by a gift');
			Assert.areEqual(String.valueOf(first.Id), single[0].Gift_Id__c, 'the gift is recorded');
			List<Membership_Term__c> recurring = termsOf(monthly.Id);
			Assert.areEqual(1, recurring.size(), 'the monthly giver joined');
			Assert.areEqual('Recurring Gift', recurring[0].Source__c, 'paid by a recurring gift');
			Assert.areEqual(String.valueOf(second.Id), recurring[0].Gift_Id__c, 'its gift');
			Assert.areEqual(0, MembershipRenewals.renewFromGifts(), 'a gift pays only once');

			// Two years on both terms have ended; the active commitment renews only its member.
			MembershipService.todayOverride = TODAY.addYears(2);
			Assert.areEqual(2, MembershipRenewals.lapse(), 'both ended terms moved');
			Assert.areEqual(
				'Lapsed',
				[SELECT Status__c FROM Membership_Term__c WHERE Id = :single[0].Id WITH USER_MODE]
				.Status__c,
				'no recurring gift: it lapses'
			);
			Assert.areEqual(
				2,
				termsOf(monthly.Id).size(),
				'the active commitment renewed its term'
			);
		}
	}
}
