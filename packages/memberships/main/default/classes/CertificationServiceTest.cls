/**
 * Certifications and continuing credits (G-22e, canonical model R-MEM10 to R-MEM13): granting,
 * renewing once enough credits are earned, the nightly expiry, revoking, and erasure. These
 * tests have not been executed: no org in this environment.
 */
@IsTest(
	testFor='ApexClass:CertificationService, ApexClass:CertificationController, ApexClass:MembershipsErasureExtension'
)
private class CertificationServiceTest {
	private static final String ADMIN = 'Memberships_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN);
	}

	private static Member_Certification__c holding(Decimal creditsRequired, Decimal months) {
		Certification__c certification = new Certification__c(
			Name = 'Certified Trainer',
			Credits_Required__c = creditsRequired,
			Valid_Months__c = months
		);
		insert as user certification;
		Contact person = TestDataFactory.person(new Contact(LastName = 'Trainer'));
		insert as user person;
		Member_Certification__c holding = new Member_Certification__c(
			Certification__c = certification.Id,
			Contact__c = person.Id,
			Notes__c = 'Passed the exam'
		);
		insert as user holding;
		return holding;
	}

	private static void credit(Id holdingId, Decimal credits) {
		insert as user new Continuing_Credit__c(
			Member_Certification__c = holdingId,
			Credits__c = credits,
			Activity__c = 'Workshop'
		);
	}

	private static Member_Certification__c reread(Id holdingId) {
		return [
			SELECT Status__c, Earned_On__c, Expires_On__c, Open_Credits__c, Notes__c
			FROM Member_Certification__c
			WHERE Id = :holdingId
		];
	}

	@IsTest
	static void grantMakesItActiveFromTodayForItsValidMonths() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Member_Certification__c made = holding(10, 24);
			CertificationController.Panel panel = CertificationController.panel(made.Id);
			Assert.areEqual('Pending', panel.status);
			Assert.isTrue(panel.canGrant);

			panel = CertificationController.grant(made.Id);
			Member_Certification__c held = reread(made.Id);
			Assert.areEqual('Active', held.Status__c);
			Assert.areEqual(Date.today(), held.Earned_On__c);
			Assert.areEqual(Date.today().addMonths(24).addDays(-1), held.Expires_On__c);
			Assert.isFalse(panel.canGrant, 'Already Active.');
			Assert.isNotNull(panel.renewRefusal, 'No credits yet.');
		}
	}

	@IsTest
	static void renewNeedsTheCreditsThenExtendsFromTheOldEndAndUsesThem() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Member_Certification__c made = holding(10, 12);
			CertificationService.grant(made.Id);
			Date firstEnd = reread(made.Id).Expires_On__c;
			credit(made.Id, 4);
			try {
				CertificationController.renew(made.Id);
				Assert.fail('Too few credits.');
			} catch (AuraHandledException refused) {
				Assert.isTrue(refused.getMessage().contains('4'), refused.getMessage());
			}
			credit(made.Id, 6.5);
			CertificationController.renew(made.Id);
			Member_Certification__c renewed = reread(made.Id);
			Assert.areEqual(firstEnd.addDays(1).addMonths(12).addDays(-1), renewed.Expires_On__c);
			Assert.areEqual(0, renewed.Open_Credits__c, 'The credits were used.');
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Continuing_Credit__c WHERE Used__c = TRUE],
				'Both credits marked Used.'
			);
		}
	}

	@IsTest
	static void nightlyExpiryEndsPastCertificationsAndAnExpiredOneRenewsFromToday() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Member_Certification__c made = holding(0, 12);
			update as user new Member_Certification__c(
				Id = made.Id,
				Status__c = 'Active',
				Expires_On__c = Date.today().addDays(-3)
			);
			Assert.areEqual(1, CertificationService.expire());
			Assert.areEqual('Expired', reread(made.Id).Status__c);

			CertificationService.renew(made.Id);
			Assert.areEqual(Date.today().addMonths(12).addDays(-1), reread(made.Id).Expires_On__c);
		}
	}

	@IsTest
	static void revokedAndNeverExpiringCertificationsAreNotRenewed() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Member_Certification__c lifetime = holding(0, 0);
			CertificationService.grant(lifetime.Id);
			Assert.isNull(reread(lifetime.Id).Expires_On__c, 'Never expires.');
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Cert_ErrorNeverExpires'),
				CertificationController.panel(lifetime.Id).renewRefusal
			);
			CertificationController.revoke(lifetime.Id);
			Assert.areEqual('Revoked', reread(lifetime.Id).Status__c);
			Assert.areEqual(
				BarnHelp.text('Memberships', 'Memberships_Cert_ErrorNotHeld'),
				CertificationController.panel(lifetime.Id).renewRefusal
			);
		}
	}

	@IsTest
	static void erasureClearsNotesAndCreditActivity() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Member_Certification__c made = holding(0, 12);
			credit(made.Id, 1);
			Id personId = [SELECT Contact__c FROM Member_Certification__c WHERE Id = :made.Id]
			.Contact__c;
			new MembershipsErasureExtension().erase(personId);
			Assert.isNull(reread(made.Id).Notes__c);
			Assert.isNull([SELECT Activity__c FROM Continuing_Credit__c LIMIT 1].Activity__c);
		}
	}
}
