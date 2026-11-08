/**
 * The secrets Portal Builder's sign-in uses (ADR-0185
 * `0185-portal-builder-off-platform-portal-api.md`, decisions 4 to 6): random tokens and codes
 * from `Crypto`, SHA-256 hashes (the only form they are stored in), a constant-time comparison,
 * and time-based authenticator codes (TOTP, RFC 6238: HMAC-SHA1, 30-second steps, six digits).
 * No state and no database.
 */
public with sharing class PortalTokens {
	private static final String BASE32_LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
	private static final String HEX_DIGITS = '0123456789abcdef';
	private static final Long STEP_SECONDS = 30;
	/** Codes from the step before and after are accepted too, for a clock a little off. */
	private static final Integer DRIFT_STEPS = 1;

	/** A new random token: 256 bits, URL-safe base64 with no padding (43 characters). */
	public static String newToken() {
		return EncodingUtil.base64Encode(Crypto.generateAesKey(256))
			.replace('+', '-')
			.replace('/', '_')
			.replace('=', '');
	}

	/** SHA-256 of the text, as 64 lower-case hex characters. */
	public static String hash(String value) {
		return EncodingUtil.convertToHex(
			Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value))
		);
	}

	/** A new six-digit code, with leading zeros. */
	public static String newCode() {
		Long random = Crypto.getRandomLong();
		Long positive = random < 0 ? -(random + 1) : random;
		return String.valueOf(Math.mod(positive, 1000000)).leftPad(6, '0');
	}

	/** Whether two texts are equal, taking the same time wherever they differ. */
	public static Boolean sameText(String a, String b) {
		if (a == null || b == null || a.length() != b.length()) {
			return false;
		}
		Integer difference = 0;
		for (Integer i = 0; i < a.length(); i++) {
			difference |= a.charAt(i) ^ b.charAt(i);
		}
		return difference == 0;
	}

	/** A new authenticator secret: 160 random bits as base32 (32 characters). */
	public static String newSecret() {
		String hex = EncodingUtil.convertToHex(Crypto.generateAesKey(256)).substring(0, 40);
		return base32FromHex(hex);
	}

	/** The `otpauth://` address an authenticator app reads, usually from a QR code. */
	public static String enrolmentUri(String issuer, String account, String secret) {
		String label = EncodingUtil.urlEncode(issuer + ':' + account, 'UTF-8').replace('+', '%20');
		return 'otpauth://totp/' +
			label +
			'?secret=' +
			secret +
			'&issuer=' +
			EncodingUtil.urlEncode(issuer, 'UTF-8').replace('+', '%20') +
			'&algorithm=SHA1&digits=6&period=30';
	}

	/** Whether the code is the secret's code now, or one step either side. */
	public static Boolean authenticatorCodeMatches(String secret, String code, Datetime now) {
		if (String.isBlank(secret) || code == null || !code.trim().isNumeric()) {
			return false;
		}
		Long step = now.getTime() / 1000 / STEP_SECONDS;
		Boolean matched = false;
		for (Integer drift = -DRIFT_STEPS; drift <= DRIFT_STEPS; drift++) {
			// Every step is checked, so a match takes the same time wherever it is found.
			matched = sameText(authenticatorCode(secret, step + drift), code.trim()) || matched;
		}
		return matched;
	}

	/** The six-digit code for a base32 secret at one 30-second step (RFC 6238, RFC 4226). */
	@TestVisible
	private static String authenticatorCode(String secret, Long step) {
		Blob key = EncodingUtil.convertFromHex(hexFromBase32(secret));
		Blob counter = EncodingUtil.convertFromHex(hexOf(step, 16));
		String mac = EncodingUtil.convertToHex(Crypto.generateMac('hmacSHA1', counter, key));
		Integer offset = HEX_DIGITS.indexOf(mac.substring(39, 40));
		Long binary = longFromHex(mac.substring(offset * 2, offset * 2 + 8)) & 2147483647L;
		return String.valueOf(Math.mod(binary, 1000000L)).leftPad(6, '0');
	}

	private static String hexOf(Long value, Integer digits) {
		String out = '';
		Long rest = value;
		for (Integer i = 0; i < digits; i++) {
			Integer nibble = (Integer) Math.mod(rest, 16L);
			out = HEX_DIGITS.substring(nibble, nibble + 1) + out;
			rest = rest / 16;
		}
		return out;
	}

	private static Long longFromHex(String hex) {
		Long value = 0;
		for (Integer i = 0; i < hex.length(); i++) {
			value = value * 16 + HEX_DIGITS.indexOf(hex.substring(i, i + 1));
		}
		return value;
	}

	@TestVisible
	private static String base32FromHex(String hex) {
		String bits = '';
		for (Integer i = 0; i < hex.length(); i++) {
			Integer nibble = HEX_DIGITS.indexOf(hex.substring(i, i + 1).toLowerCase());
			bits += bitsOf(nibble, 4);
		}
		String out = '';
		for (Integer i = 0; i + 5 <= bits.length(); i += 5) {
			Integer index = Integer.valueOf(longFromBits(bits.substring(i, i + 5)));
			out += BASE32_LETTERS.substring(index, index + 1);
		}
		return out;
	}

	@TestVisible
	private static String hexFromBase32(String secret) {
		String bits = '';
		for (String letter : secret.toUpperCase().replace('=', '').replace(' ', '').split('')) {
			Integer index = BASE32_LETTERS.indexOf(letter);
			if (index < 0) {
				throw new IllegalArgumentException('Not base32');
			}
			bits += bitsOf(index, 5);
		}
		String hex = '';
		for (Integer i = 0; i + 4 <= bits.length() - Math.mod(bits.length(), 8); i += 4) {
			Integer nibble = Integer.valueOf(longFromBits(bits.substring(i, i + 4)));
			hex += HEX_DIGITS.substring(nibble, nibble + 1);
		}
		return hex;
	}

	private static String bitsOf(Integer value, Integer width) {
		String out = '';
		Integer rest = value;
		for (Integer i = 0; i < width; i++) {
			out = String.valueOf(Math.mod(rest, 2)) + out;
			rest = rest / 2;
		}
		return out;
	}

	private static Long longFromBits(String bits) {
		Long value = 0;
		for (Integer i = 0; i < bits.length(); i++) {
			value = value * 2 + (bits.substring(i, i + 1) == '1' ? 1 : 0);
		}
		return value;
	}
}
