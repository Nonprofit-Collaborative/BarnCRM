/**
 * Pat signs in to a portal with a code Salesforce emails and checks; nobody learns who is on
 * file; wrong codes lock; the second factor works; and staff end sessions from Salesforce
 * (ADR-0185 `0185-portal-builder-off-platform-portal-api.md`, decisions 4 to 7).
 */
@IsTest(testFor='ApexClass:PortalAuth')
private class PortalAuthTest {
	private static final String EMAIL = 'pat.zzportal@example.org';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Portal_Admin');
	}

	private static String refusal(Callable call) {
		try {
			call.call('run', null);
		} catch (PortalAuth.RefusalException refused) {
			return refused.getMessage();
		}
		return null;
	}

	private class Verify implements Callable {
		String challenge;
		String code;

		Verify(String challenge, String code) {
			this.challenge = challenge;
			this.code = code;
		}

		public Object call(String action, Map<String, Object> args) {
			return PortalAuth.verifyCode(challenge, code);
		}
	}

	private class SecondFactor implements Callable {
		String challenge;
		String code;

		SecondFactor(String challenge, String code) {
			this.challenge = challenge;
			this.code = code;
		}

		public Object call(String action, Map<String, Object> args) {
			return PortalAuth.verifySecondFactor(challenge, code);
		}
	}

	private class Resolve implements Callable {
		String token;

		Resolve(String token) {
			this.token = token;
		}

		public Object call(String action, Map<String, Object> args) {
			return PortalAuth.resolve(token);
		}
	}

	private static Integer sessions() {
		return [SELECT COUNT() FROM Portal_Session__c];
	}

	@IsTest
	static void signsInWithTheEmailedCodeAndKeepsOnlyHashes() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			Portal__c portal = PortalTestData.portal('Invited', 'Off');
			PortalTestData.access(portal, PortalTestData.person('Zzportal', EMAIL));

			Test.startTest();
			String challenge = PortalAuth.start(PortalTestData.KEY, '  Pat.Zzportal@Example.org ');
			String code = PortalAuth.lastCodeForTest;
			Map<String, Object> result = PortalAuth.verifyCode(challenge, code);
			Integer queriesBefore = Limits.getQueries();
			PortalAuth.Session session = PortalAuth.resolve((String) result.get('session'));
			Integer resolveQueries = Limits.getQueries() - queriesBefore;
			Test.stopTest();

			Assert.areEqual(
				1,
				resolveQueries,
				'Every signed-in request reads its session, access, person and portal in one query'
			);
			Assert.areEqual(PortalTestData.KEY, session.portal.Key__c, 'The portal comes with it');

			Assert.areEqual('signedIn', result.get('status'), 'Signed in');
			Portal_Session__c stored = [
				SELECT Stage__c, Token_Hash__c, Code_Hash__c, Expires__c
				FROM Portal_Session__c
				WITH SYSTEM_MODE
				LIMIT 1
			];
			Assert.areEqual('Active', stored.Stage__c, 'The session is active');
			Assert.areEqual(
				PortalTokens.hash((String) result.get('session')),
				stored.Token_Hash__c,
				'Only the hash'
			);
			Assert.isNull(stored.Code_Hash__c, 'The code is forgotten once used');
			Assert.isNotNull(session.personId(), 'The session names the person');
			Assert.areEqual(
				'code_invalid',
				refusal(new Verify(challenge, code)),
				'A code works once'
			);
		}
	}

	@IsTest
	static void anUnknownEmailGetsTheSameAnswerAndNoEmail() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			PortalTestData.portal('Invited', 'Off');
			PortalTestData.person('Zzportal', EMAIL);

			Test.startTest();
			String unknown = PortalAuth.start(PortalTestData.KEY, 'nobody@example.org');
			String notInvited = PortalAuth.start(PortalTestData.KEY, EMAIL);
			Test.stopTest();

			Assert.areEqual(43, unknown.length(), 'A challenge like any other');
			Assert.areEqual(43, notInvited.length(), 'Even for a person not invited');
			Assert.areEqual(0, sessions(), 'No code was sent');
			Assert.areEqual(
				'code_invalid',
				refusal(new Verify(unknown, '123456')),
				'It matches nothing'
			);
		}
	}

	@IsTest
	static void anyMatchingPersonPortalsLetAPersonOnFileIn() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			PortalTestData.portal('Any Matching Person', 'Off');
			PortalTestData.person('Zzportal', EMAIL);
			PortalTestData.person('Zztwin', 'twin@example.org');
			PortalTestData.person('Zztwin', 'twin@example.org');

			Test.startTest();
			String token = PortalTestData.signIn(EMAIL);
			PortalAuth.start(PortalTestData.KEY, 'twin@example.org');
			Test.stopTest();

			Assert.isNotNull(token, 'The person on file signed in');
			Assert.areEqual(1, [SELECT COUNT() FROM Portal_Access__c], 'An access was made, once');
			Assert.areEqual(1, sessions(), 'Two people sharing an email get no code');
		}
	}

	@IsTest
	static void wrongCodesEndTheChallengeAndLockThePerson() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			Portal_Settings__c settings = Portal_Settings__c.getOrgDefaults();
			settings.Failures_Before_Lockout__c = 3;
			upsert settings;
			Portal__c portal = PortalTestData.portal('Invited', 'Off');
			PortalTestData.access(portal, PortalTestData.person('Zzportal', EMAIL));

			Test.startTest();
			String challenge = PortalAuth.start(PortalTestData.KEY, EMAIL);
			String right = PortalAuth.lastCodeForTest;
			String wrong = right == '000000' ? '111111' : '000000';
			List<String> answers = new List<String>();
			for (Integer i = 0; i < 3; i++) {
				answers.add(refusal(new Verify(challenge, wrong)));
			}
			answers.add(refusal(new Verify(challenge, right)));
			PortalAuth.start(PortalTestData.KEY, EMAIL);
			Test.stopTest();

			Assert.areEqual('code_invalid', answers[0], 'A wrong code is refused');
			Assert.areEqual(
				'code_invalid',
				answers[3],
				'Once locked out, the right code fails too'
			);
			Portal_Access__c access = [SELECT Locked_Until__c FROM Portal_Access__c LIMIT 1];
			Assert.isNotNull(access.Locked_Until__c, 'The person is locked out');
			Assert.areEqual(1, sessions(), 'No code is sent while locked');
		}
	}

	/**
	 * A wrong code answers code_invalid whether the address is on file, expired or locked out;
	 * expiry and lockout are told only after the right code (R-PST1).
	 */
	@IsTest
	static void aWrongCodeNeverSaysWhoIsOnFile() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			Portal_Settings__c settings = Portal_Settings__c.getOrgDefaults();
			settings.Failures_Before_Lockout__c = 3;
			upsert settings;
			Portal__c portal = PortalTestData.portal('Invited', 'Off');
			PortalTestData.access(portal, PortalTestData.person('Zzportal', EMAIL));

			Test.startTest();
			String nobody = PortalAuth.start(PortalTestData.KEY, 'nobody.zzportal@example.org');
			String expiring = PortalAuth.start(PortalTestData.KEY, EMAIL);
			String late = PortalAuth.start(PortalTestData.KEY, EMAIL);
			String lateCode = PortalAuth.lastCodeForTest;
			String held = PortalAuth.start(PortalTestData.KEY, EMAIL);
			String heldCode = PortalAuth.lastCodeForTest;
			String burnt = PortalAuth.start(PortalTestData.KEY, EMAIL);
			String wrong = heldCode == '000000' ? '111111' : '000000';
			List<String> answers = new List<String>{ refusal(new Verify(nobody, wrong)) };
			PortalAuth.nowForTest = Datetime.now().addMinutes(11);
			answers.add(refusal(new Verify(expiring, wrong)));
			answers.add(refusal(new Verify(late, lateCode)));
			PortalAuth.nowForTest = null;
			for (Integer i = 0; i < 3; i++) {
				refusal(new Verify(burnt, wrong));
			}
			answers.add(refusal(new Verify(held, wrong)));
			answers.add(refusal(new Verify(held, heldCode)));
			Test.stopTest();

			Assert.areEqual(
				new List<String>{
					'code_invalid',
					'code_invalid',
					'code_expired',
					'code_invalid',
					'locked'
				},
				answers,
				'Not on file, expired and wrong, expired and right, locked and wrong, locked and right'
			);
		}
	}

	@IsTest
	static void limitsSendNothingAndLookTheSame() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			Portal_Settings__c settings = Portal_Settings__c.getOrgDefaults();
			settings.Code_Requests_Per_Hour__c = 1;
			upsert settings;
			Portal__c portal = PortalTestData.portal('Invited', 'Off');
			PortalTestData.access(portal, PortalTestData.person('Zzportal', EMAIL));

			Test.startTest();
			String first = PortalAuth.start(PortalTestData.KEY, EMAIL);
			String second = PortalAuth.start(PortalTestData.KEY, EMAIL);
			Test.stopTest();

			Assert.areEqual(first.length(), second.length(), 'The same answer');
			Assert.areEqual(1, sessions(), 'Only the first sent a code');
		}
	}

	@IsTest
	static void aRequiredSecondFactorIsEnrolledThenAsked() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			Portal__c portal = PortalTestData.portal('Invited', 'Required');
			PortalTestData.access(portal, PortalTestData.person('Zzportal', EMAIL));
			Long step = Datetime.now().getTime() / 1000 / 30;

			Test.startTest();
			String challenge = PortalAuth.start(PortalTestData.KEY, EMAIL);
			Map<String, Object> enrol = PortalAuth.verifyCode(
				challenge,
				PortalAuth.lastCodeForTest
			);
			String secret = (String) enrol.get('secret');
			Map<String, Object> first = PortalAuth.verifySecondFactor(
				challenge,
				PortalTokens.authenticatorCode(secret, step)
			);
			String again = PortalAuth.start(PortalTestData.KEY, EMAIL);
			Map<String, Object> asked = PortalAuth.verifyCode(again, PortalAuth.lastCodeForTest);
			String replayed = refusal(
				new SecondFactor(again, PortalTokens.authenticatorCode(secret, step))
			);
			Map<String, Object> second = PortalAuth.verifySecondFactor(
				again,
				PortalTokens.authenticatorCode(secret, step + 1)
			);
			Test.stopTest();

			Assert.areEqual('code_invalid', replayed, 'A code already used is refused (R-PA3)');
			Decimal lastStep = [SELECT Second_Factor_Last_Step__c FROM Portal_Access__c LIMIT 1]
			.Second_Factor_Last_Step__c;
			Assert.areEqual(step + 1, lastStep.longValue(), 'The last step used is kept');

			Assert.areEqual('enroll', enrol.get('status'), 'Enrolment first');
			Assert.isTrue(
				((String) enrol.get('uri')).startsWith('otpauth://totp/'),
				'For an authenticator app'
			);
			Assert.areEqual('signedIn', first.get('status'), 'Signed in after enrolling');
			Assert.areEqual('secondFactor', asked.get('status'), 'Asked for the code next time');
			Assert.areEqual('signedIn', second.get('status'), 'And signed in with it');
			Assert.isTrue(
				[SELECT Second_Factor_Enrolled__c FROM Portal_Access__c LIMIT 1]
				.Second_Factor_Enrolled__c,
				'Enrolled'
			);
		}
	}

	@IsTest
	static void staffEndSessionsFromSalesforce() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.enable();
			Portal__c portal = PortalTestData.portal('Invited', 'Off');
			Portal_Access__c access = PortalTestData.access(
				portal,
				PortalTestData.person('Zzportal', EMAIL)
			);
			String suspended = PortalTestData.signIn(EMAIL);
			String idle = PortalTestData.signIn(EMAIL);
			String signedOut = PortalTestData.signIn(EMAIL);

			Test.startTest();
			PortalAuth.signOut(signedOut);
			String afterSignOut = refusal(new Resolve(signedOut));
			PortalAuth.nowForTest = Datetime.now().addMinutes(31);
			String afterIdle = refusal(new Resolve(idle));
			PortalAuth.nowForTest = null;
			update new Portal_Access__c(Id = access.Id, Status__c = 'Suspended');
			String afterSuspend = refusal(new Resolve(suspended));
			Test.stopTest();

			Assert.areEqual('not_signed_in', afterSignOut, 'Signed out');
			Assert.areEqual('not_signed_in', afterIdle, 'Idle too long');
			Assert.areEqual('not_signed_in', afterSuspend, 'Suspended');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Portal_Session__c WHERE Stage__c = 'Active'],
				'Every session ended'
			);
		}
	}

	@IsTest
	static void nothingWorksWhilePortalSignInIsOff() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			PortalTestData.portal('Invited', 'Off');

			Test.startTest();
			String answer;
			try {
				PortalAuth.start(PortalTestData.KEY, EMAIL);
			} catch (PortalAuth.RefusalException refused) {
				answer = refused.getMessage();
			}
			Test.stopTest();

			Assert.areEqual('portal_unavailable', answer, 'Off until the admin turns it on');
		}
	}
}
