/**
 * Today's date for business rules: one org-wide date, read in the org's default time zone
 * (Setup, Company Information), never in the running user's (plan D-208, N-03).
 *
 * `Date.today()` answers in the running user's time zone, so the same rule gave different
 * answers to different people: a membership ended today by an eraser in London still read as
 * current to a colleague in California that evening. Every Core date rule (memberships and
 * addresses that end, retention windows, seasonal addresses, scores) asks this class instead,
 * and modules may adopt it the same way.
 *
 * Pure display (a file name, a date shown to the person) keeps the person's own date.
 *
 * The org's time zone is read once per transaction and today's date is cached with it, so a
 * rule can call this in a loop for free. Tests set `zoneOverride` (a time zone ID) or
 * `todayOverride` and call `reset()`.
 */
@NamespaceAccessible
public with sharing class OrgDate {
	@TestVisible
	private static String zoneOverride;
	@TestVisible
	private static Date todayOverride;

	private static TimeZone cachedZone;
	private static Date cachedToday;

	/** Today's date in the org's default time zone. */
	@NamespaceAccessible
	public static Date today() {
		if (todayOverride != null) {
			return todayOverride;
		}
		if (cachedToday == null) {
			cachedToday = dateIn(Datetime.now(), zone());
		}
		return cachedToday;
	}

	/** The org's default time zone; the running user's when it cannot be read. */
	@NamespaceAccessible
	public static TimeZone zone() {
		if (cachedZone == null) {
			String zoneId = String.isNotBlank(zoneOverride) ? zoneOverride : readOrgZoneId();
			cachedZone = String.isBlank(zoneId) ? UserInfo.getTimeZone() : TimeZone.getTimeZone(zoneId);
		}
		return cachedZone;
	}

	/** The calendar date a moment falls on in the given time zone. */
	@TestVisible
	private static Date dateIn(Datetime moment, TimeZone zone) {
		return Date.valueOf(moment.format('yyyy-MM-dd', zone.getID()));
	}

	/** Forgets the cached zone and date, for tests that change the overrides. */
	@TestVisible
	private static void reset() {
		cachedZone = null;
		cachedToday = null;
	}

	private static String readOrgZoneId() {
		try {
			// The org's time zone is org-wide setup data every user sees in Setup; reading it
			// in system mode reveals nothing beyond that.
			List<Organization> organizations = [
				SELECT TimeZoneSidKey
				FROM Organization
				WITH SYSTEM_MODE
				LIMIT 1
			];
			return organizations.isEmpty() ? null : organizations[0].TimeZoneSidKey;
		} catch (QueryException cannotRead) {
			return null;
		}
	}
}
