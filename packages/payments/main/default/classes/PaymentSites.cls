/**
 * The org's active Salesforce Sites, for the webhook receiver (ADR-0201
 * `0201-payments-module.md`, decision 4): their guest users, for Health Check, and their secure
 * addresses, for the receiver addresses on Payments Setup. Experience Cloud sites are left out
 * (ADR-0009). The same reading as Forms' `FormsSites`, kept here because Payments depends on
 * Core only.
 *
 * Site and SiteDetail are setup records with no sharing; they are read in system mode so a
 * Payments admin without View Setup still sees the addresses.
 */
public with sharing class PaymentSites {
	private static final Integer SITE_LIMIT = 50;
	/** The receiver's path under a Site's address; the processor's name follows it. */
	public static final String RECEIVER_PATH = '/services/apexrest/barncrm/payments/v1/';

	/** One active Site. */
	public class SiteInfo {
		public String name;
		public Id guestUserId;
		/** The secure base address, with no trailing slash; null when Salesforce has none. */
		public String url;
	}

	/** Set by tests: the Sites to report, since a test org may have none. */
	@TestVisible
	private static List<SiteInfo> testSites;

	private static List<SiteInfo> cached;

	/** The active Salesforce Sites, by name. */
	public static List<SiteInfo> active() {
		if (testSites != null) {
			return testSites;
		}
		if (cached != null) {
			return cached;
		}
		List<Site> sites = [
			SELECT Id, MasterLabel, GuestUserId
			FROM Site
			WHERE Status = 'Active' AND SiteType = 'Visualforce'
			WITH SYSTEM_MODE
			ORDER BY MasterLabel
			LIMIT :SITE_LIMIT
		];
		Set<String> durableIds = new Set<String>();
		for (Site one : sites) {
			durableIds.add(String.valueOf(one.Id).left(15));
			durableIds.add(String.valueOf(one.Id));
		}
		Map<String, String> urlByShortId = new Map<String, String>();
		if (!sites.isEmpty()) {
			for (SiteDetail detail : [
				SELECT DurableId, SecureUrl
				FROM SiteDetail
				WHERE DurableId IN :durableIds
				WITH SYSTEM_MODE
			]) {
				urlByShortId.put(detail.DurableId.left(15), detail.SecureUrl);
			}
		}
		cached = new List<SiteInfo>();
		for (Site one : sites) {
			SiteInfo info = new SiteInfo();
			info.name = one.MasterLabel;
			info.guestUserId = one.GuestUserId;
			String url = urlByShortId.get(String.valueOf(one.Id).left(15));
			info.url = url == null ? null : url.removeEnd('/');
			cached.add(info);
		}
		return cached;
	}

	/** The guest users of the active Sites. */
	public static Set<Id> guestUserIds() {
		Set<Id> ids = new Set<Id>();
		for (SiteInfo site : active()) {
			if (site.guestUserId != null) {
				ids.add(site.guestUserId);
			}
		}
		return ids;
	}
}
