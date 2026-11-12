/**
 * Certifications and continuing credits (G-22e, canonical model 29MEM5 to 29MEM7): granting
 * (R-MEM10), renewing once enough credits are earned (R-MEM11) and the nightly expiry (R-MEM12).
 * Grant, Renew and Revoke run as the person, in user mode; the nightly expiry acts for the
 * organization, in system mode, as the rest of the Memberships step does.
 */
public with sharing class CertificationService {
	public static final String PENDING = 'Pending';
	public static final String ACTIVE = 'Active';
	public static final String EXPIRED = 'Expired';
	public static final String REVOKED = 'Revoked';
	private static final Integer EXPIRE_ROWS = 2000;

	public class CertificationException extends Exception {
	}

	/** Makes a Pending, Expired or Revoked certification Active from today (R-MEM10). */
	public static void grant(Id holdingId) {
		Member_Certification__c holding = read(holdingId);
		if (holding.Status__c == ACTIVE) {
			throw new CertificationException(
				BarnHelp.text('Memberships', 'Memberships_Cert_ErrorActive')
			);
		}
		Date today = MembershipService.today();
		holding.Status__c = ACTIVE;
		holding.Earned_On__c = holding.Earned_On__c == null ? today : holding.Earned_On__c;
		holding.Expires_On__c = endOf(today, holding.Certification__r.Valid_Months__c);
		save(holding);
	}

	/** Renews an Active or Expired certification once its credits reach those required (R-MEM11). */
	public static void renew(Id holdingId) {
		Member_Certification__c holding = read(holdingId);
		String refusal = renewRefusal(holding);
		if (refusal != null) {
			throw new CertificationException(refusal);
		}
		Date today = MembershipService.today();
		Date start = holding.Status__c == ACTIVE &&
			holding.Expires_On__c >= today
			? holding.Expires_On__c.addDays(1)
			: today;
		holding.Status__c = ACTIVE;
		holding.Expires_On__c = endOf(start, holding.Certification__r.Valid_Months__c);
		List<Continuing_Credit__c> used = new List<Continuing_Credit__c>();
		for (Continuing_Credit__c credit : [
			SELECT Id
			FROM Continuing_Credit__c
			WHERE Member_Certification__c = :holdingId AND Used__c = FALSE
			WITH USER_MODE
		]) {
			used.add(new Continuing_Credit__c(Id = credit.Id, Used__c = true));
		}
		Savepoint before = Database.setSavepoint();
		try {
			save(holding);
			Database.update(used, AccessLevel.USER_MODE);
		} catch (Exception e) {
			Database.rollback(before);
			throw e;
		}
	}

	/** Ends a certification now. */
	public static void revoke(Id holdingId) {
		Member_Certification__c holding = read(holdingId);
		holding.Status__c = REVOKED;
		save(holding);
	}

	/** Why Renew is refused, or null when it is allowed. */
	public static String renewRefusal(Member_Certification__c holding) {
		if (holding.Status__c != ACTIVE && holding.Status__c != EXPIRED) {
			return BarnHelp.text('Memberships', 'Memberships_Cert_ErrorNotHeld');
		}
		Decimal months = holding.Certification__r.Valid_Months__c;
		if (months == null || months <= 0 || holding.Expires_On__c == null) {
			return BarnHelp.text('Memberships', 'Memberships_Cert_ErrorNeverExpires');
		}
		Decimal open = holding.Open_Credits__c == null ? 0 : holding.Open_Credits__c;
		Decimal needed = holding.Certification__r.Credits_Required__c == null
			? 0
			: holding.Certification__r.Credits_Required__c;
		if (open < needed) {
			return String.format(
				BarnHelp.text('Memberships', 'Memberships_Cert_ErrorCredits'),
				new List<Object>{ open.format(), needed.format() }
			);
		}
		return null;
	}

	/** Each night: Active certifications past their Expires On become Expired (R-MEM12). */
	public static Integer expire() {
		List<Member_Certification__c> ended = new List<Member_Certification__c>();
		for (Member_Certification__c holding : [
			SELECT Id
			FROM Member_Certification__c
			WHERE Status__c = :ACTIVE AND Expires_On__c < TODAY
			WITH SYSTEM_MODE
			LIMIT :EXPIRE_ROWS
		]) {
			ended.add(new Member_Certification__c(Id = holding.Id, Status__c = EXPIRED));
		}
		Database.update(ended, false, AccessLevel.SYSTEM_MODE);
		return ended.size();
	}

	/** The last day of a period of `months` from `start`, or null when it never ends. */
	@TestVisible
	private static Date endOf(Date start, Decimal months) {
		return months == null ||
			months <= 0
			? null
			: start.addMonths(months.intValue()).addDays(-1);
	}

	public static Member_Certification__c read(Id holdingId) {
		List<Member_Certification__c> found = [
			SELECT
				Id,
				Status__c,
				Earned_On__c,
				Expires_On__c,
				Open_Credits__c,
				Certification__r.Valid_Months__c,
				Certification__r.Credits_Required__c
			FROM Member_Certification__c
			WHERE Id = :holdingId
			WITH USER_MODE
			LIMIT 1
		];
		if (found.isEmpty()) {
			throw new CertificationException(
				BarnHelp.text('Memberships', 'Memberships_Cert_ErrorNotFound')
			);
		}
		return found[0];
	}

	private static void save(Member_Certification__c holding) {
		Database.update(
			new Member_Certification__c(
				Id = holding.Id,
				Status__c = holding.Status__c,
				Earned_On__c = holding.Earned_On__c,
				Expires_On__c = holding.Expires_On__c
			),
			AccessLevel.USER_MODE
		);
	}
}
