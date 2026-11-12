/**
 * Membership terms (canonical model R-MEM1 to R-MEM3, R-MEM8): what a new term fills in,
 * renewing on time and after a lapse, what cannot be renewed, the staff panel, and erasure.
 */
@IsTest(
	testFor='ApexClass:MembershipService, ApexClass:MembershipTermHandler, ApexClass:MembershipController, ApexClass:MembershipsErasureExtension'
)
private class MembershipServiceTest {
	private static final String ADMIN = 'Memberships_Admin';

	/** Payments installed but without its keys. */
	private class NotReady implements Callable {
		public Object call(String action, Map<String, Object> args) {
			return false;
		}
	}

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN);
	}

	@IsTest
	static void theTermTriggerHandlerNamesItselfForTheRegistry() {
		// runs-as: deploying user (reads a name; touches no data or permissions)
		Assert.areEqual(
			'MembershipTermHandler',
			new MembershipTermHandler().getName(),
			'The registry row Membership_Term_Dates runs this handler by its name'
		);
	}

	private static Membership_Level__c level(String name, Decimal dues, Decimal months) {
		Membership_Level__c level = new Membership_Level__c(
			Name = name,
			Dues__c = dues,
			Term_Months__c = months,
			Grace_Days__c = 30
		);
		insert as user level;
		return level;
	}

	private static Membership_Term__c term(Id levelId, Id contactId, String status, Date starts) {
		Membership_Term__c term = new Membership_Term__c(
			Level__c = levelId,
			Contact__c = contactId,
			Status__c = status,
			Start_Date__c = starts
		);
		insert as user term;
		return [
			SELECT Id, Status__c, Dues__c, Start_Date__c, End_Date__c, Member_Since__c
			FROM Membership_Term__c
			WHERE Id = :term.Id
			WITH USER_MODE
		];
	}

	private static Contact person() {
		Contact person = new Contact(LastName = 'Zzmem Member', Email = 'member@example.org');
		// An org's duplicate rule must not stop a test person sharing an email.
		Database.DMLOptions options = new Database.DMLOptions();
		options.DuplicateRuleHeader.allowSave = true;
		Database.insert(person, options, AccessLevel.USER_MODE);
		return person;
	}

	@IsTest
	static void aNewTermFillsDuesDatesAndMemberSince() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = Date.newInstance(2026, 3, 15);
			Membership_Level__c yearly = level('Individual', 50, 12);
			Membership_Term__c made = term(yearly.Id, person().Id, 'Current', null);
			Assert.areEqual(50, made.Dues__c, 'dues come from the level');
			Assert.areEqual(Date.newInstance(2026, 3, 15), made.Start_Date__c, 'starts today');
			Assert.areEqual(Date.newInstance(2027, 3, 14), made.End_Date__c, 'one year less a day');
			Assert.areEqual(
				made.Start_Date__c,
				made.Member_Since__c,
				'a first term starts the membership'
			);

			Membership_Level__c lifetime = level('Lifetime', 1000, 0);
			Membership_Term__c forever = term(lifetime.Id, person().Id, 'Current', null);
			Assert.isNull(forever.End_Date__c, 'a level of 0 months never ends');
			Membership_Term__c pending = term(yearly.Id, person().Id, 'Pending', null);
			Assert.isNull(pending.Start_Date__c, 'a pending term waits for its payment to start');
		}
	}

	@IsTest
	static void renewingOnTimeContinuesTheTermAndAfterALapseRejoins() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipService.todayOverride = Date.newInstance(2026, 6, 1);
			Membership_Level__c individual = level('Individual', 50, 12);
			Membership_Level__c family = level('Family', 90, 12);
			Contact member = person();
			Membership_Term__c current = term(
				individual.Id,
				member.Id,
				'Current',
				Date.newInstance(2025, 7, 1)
			);
			MembershipService.Renewal upgrade = new MembershipService.Renewal(current.Id);
			upgrade.levelId = family.Id;
			Membership_Term__c next = MembershipService.renew(
				new List<MembershipService.Renewal>{ upgrade },
				false
			)[0];
			Assert.areEqual(
				Date.newInstance(2026, 7, 1),
				next.Start_Date__c,
				'starts the day after'
			);
			Assert.areEqual('Renewal', next.Origin__c, 'renewed before it lapsed');
			Assert.areEqual(90, next.Dues__c, 'at the new level');
			Assert.areEqual(
				Date.newInstance(2025, 7, 1),
				next.Member_Since__c,
				'member since kept'
			);
			Assert.areEqual(
				'Renewed',
				[SELECT Status__c FROM Membership_Term__c WHERE Id = :current.Id WITH USER_MODE]
				.Status__c,
				'the old term is closed'
			);

			Membership_Term__c lapsed = term(
				individual.Id,
				person().Id,
				'Lapsed',
				Date.newInstance(2024, 1, 1)
			);
			Membership_Term__c rejoined = MembershipService.renew(
				new List<MembershipService.Renewal>{ new MembershipService.Renewal(lapsed.Id) },
				false
			)[0];
			Assert.areEqual(Date.newInstance(2026, 6, 1), rejoined.Start_Date__c, 'starts today');
			Assert.areEqual('Rejoin', rejoined.Origin__c, 'a lapsed member rejoins');
		}
	}

	@IsTest
	static void aRenewedTermCannotBeRenewedAgain() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Membership_Level__c individual = level('Individual', 50, 12);
			Membership_Term__c current = term(individual.Id, person().Id, 'Current', null);
			Id next = MembershipController.renew(current.Id, null);
			Assert.isNotNull(next, 'the panel renews');
			try {
				MembershipController.renew(current.Id, null);
				Assert.fail('a renewed term was renewed again');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Memberships', 'Memberships_Error_CannotRenew'),
					e.getMessage(),
					'says why in plain words'
				);
			}
		}
	}

	@IsTest
	static void thePanelSaysWhatTheTermCanDo() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			MembershipPayments.apiOverride = new NotReady();
			Membership_Level__c individual = level('Individual', 50, 12);
			Membership_Term__c current = term(individual.Id, person().Id, 'Current', null);
			MembershipController.Panel panel = MembershipController.panel(current.Id);
			Assert.isTrue(panel.canRenew, 'a current term can renew');
			Assert.isTrue(panel.hasEmail, 'the member has an email');
			Assert.isFalse(panel.paymentsReady, 'Payments is not ready');
			Assert.areEqual(1, panel.levels.size(), 'the active levels');
			try {
				MembershipController.emailPaymentLink(current.Id);
				Assert.fail('a link was queued without Payments');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Memberships', 'Memberships_Error_PaymentsNotReady'),
					e.getMessage(),
					'says Payments is not ready'
				);
			}
		}
	}

	@IsTest
	static void erasingAPersonClearsTheirListingAndNotes() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Membership_Level__c individual = level('Individual', 50, 12);
			Contact member = person();
			Membership_Term__c current = term(individual.Id, member.Id, 'Current', null);
			update as user new Membership_Term__c(
				Id = current.Id,
				Directory_Opt_In__c = true,
				Directory_Location__c = 'Springfield',
				Directory_Bio__c = 'Gardener',
				Notes__c = 'Prefers phone'
			);
			List<PersonErasure.Change> changes = new MembershipsErasureExtension().erase(member.Id);
			Assert.areEqual(1, changes.size(), 'one change reported');
			Membership_Term__c after = [
				SELECT Directory_Opt_In__c, Directory_Location__c, Directory_Bio__c, Notes__c
				FROM Membership_Term__c
				WHERE Id = :current.Id
				WITH USER_MODE
			];
			Assert.isFalse(after.Directory_Opt_In__c, 'out of the directory');
			Assert.isNull(after.Directory_Location__c, 'location cleared');
			Assert.isNull(after.Directory_Bio__c, 'bio cleared');
			Assert.isNull(after.Notes__c, 'notes cleared');
			Assert.isTrue(
				new MembershipsErasureExtension().erase(person().Id).isEmpty(),
				'nothing to clear for a non-member'
			);
		}
	}
}
