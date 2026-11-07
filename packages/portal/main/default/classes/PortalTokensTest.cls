/**
 * The sign-in secrets: hashes, codes, tokens and authenticator codes match the published test
 * vectors (RFC 6238 Appendix B, SHA-1 seed "12345678901234567890").
 */
@IsTest(testFor='ApexClass:PortalTokens')
private class PortalTokensTest {
	private static final String RFC_SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Portal_Admin');
	}

	@IsTest
	static void authenticatorCodesMatchTheRfcVectors() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Test.startTest();
			String at59 = PortalTokens.authenticatorCode(RFC_SECRET, 59L / 30);
			String at1111111109 = PortalTokens.authenticatorCode(RFC_SECRET, 1111111109L / 30);
			String at1234567890 = PortalTokens.authenticatorCode(RFC_SECRET, 1234567890L / 30);
			Test.stopTest();

			Assert.areEqual('287082', at59, 'RFC 6238 at 59 seconds (94287082)');
			Assert.areEqual('081804', at1111111109, 'RFC 6238 at 1111111109 (07081804)');
			Assert.areEqual('005924', at1234567890, 'RFC 6238 at 1234567890 (89005924)');
		}
	}

	@IsTest
	static void aCodeFromTheNextStepStillMatchesButNotOneFarOff() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Datetime at = Datetime.newInstanceGmt(2026, 11, 7, 12, 0, 0);
			Long step = at.getTime() / 1000 / 30;

			Test.startTest();
			Boolean now = PortalTokens.authenticatorCodeMatches(
				RFC_SECRET,
				PortalTokens.authenticatorCode(RFC_SECRET, step),
				at
			);
			Boolean drift = PortalTokens.authenticatorCodeMatches(
				RFC_SECRET,
				PortalTokens.authenticatorCode(RFC_SECRET, step + 1),
				at
			);
			Boolean far = PortalTokens.authenticatorCodeMatches(
				RFC_SECRET,
				PortalTokens.authenticatorCode(RFC_SECRET, step + 5),
				at
			);
			Boolean junk = PortalTokens.authenticatorCodeMatches(RFC_SECRET, 'abc', at);
			Test.stopTest();

			Assert.isTrue(now, 'The current code matches');
			Assert.isTrue(drift, 'One step of clock drift is allowed');
			Assert.isFalse(far, 'A code minutes away does not');
			Assert.isFalse(junk, 'Letters never match');
		}
	}

	@IsTest
	static void hashesTokensCodesAndSecretsHaveTheirShape() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Test.startTest();
			String hash = PortalTokens.hash('abc');
			String token = PortalTokens.newToken();
			String code = PortalTokens.newCode();
			String secret = PortalTokens.newSecret();
			Test.stopTest();

			Assert.areEqual(
				'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
				hash,
				'SHA-256 of abc'
			);
			Assert.areEqual(43, token.length(), '256 bits as URL-safe base64');
			Assert.isFalse(
				token.contains('+') || token.contains('/') || token.contains('='),
				'URL safe'
			);
			Assert.areNotEqual(token, PortalTokens.newToken(), 'Each token is new');
			Assert.isTrue(code.length() == 6 && code.isNumeric(), 'Six digits');
			Assert.areEqual(32, secret.length(), '160 bits as base32');
			Assert.areEqual(
				secret,
				PortalTokens.base32FromHex(PortalTokens.hexFromBase32(secret)),
				'Base32 reads back'
			);
			Assert.isTrue(PortalTokens.sameText('123456', '123456'), 'Equal texts match');
			Assert.isFalse(PortalTokens.sameText('123456', '123457'), 'Different texts do not');
			Assert.isFalse(PortalTokens.sameText(null, '1'), 'Nothing matches null');
			Assert.isTrue(
				PortalTokens.enrolmentUri('Sample Portal', 'pat@example.org', secret)
					.startsWith(
						'otpauth://totp/Sample%20Portal%3Apat%40example.org?secret=' + secret
					),
				'The address an authenticator app reads'
			);
		}
	}
}
