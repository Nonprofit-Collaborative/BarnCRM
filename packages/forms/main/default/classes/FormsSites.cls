/**
 * The org's active Salesforce Sites, for public forms (C-42b; ADR-0184 public forms on a
 * Salesforce Site, decision 9): their guest users, for Health Check, and their addresses, for the
 * Form Builder's public links. Experience Cloud sites are left out (ADR-0009).
 *
 * Site and SiteDetail are setup records with no sharing; they are read in system mode so a
 * Forms admin without View Setup still sees the links.
 */
public with sharing class FormsSites {
	private static final Integer SITE_LIMIT = 50;

	/** One active Site. */
	public class SiteInfo {
		public Id siteId;
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
			SELECT Id, Name, MasterLabel, GuestUserId
			FROM Site
			WHERE Status = 'Active' AND SiteType = 'Visualforce'
			WITH SYSTEM_MODE
			ORDER BY MasterLabel
			LIMIT :SITE_LIMIT
		];
		Set<String> durableIds = durableIdsOf(sites);
		cached = fromRows(
			sites,
			sites.isEmpty()
				? new List<SiteDetail>()
				: [
						SELECT DurableId, SecureUrl
						FROM SiteDetail
						WHERE DurableId IN :durableIds
						WITH SYSTEM_MODE
				  ]
		);
		return cached;
	}

	/** A Site's detail names it by its 15 or its 18 character id, so both are asked for. */
	@TestVisible
	private static Set<String> durableIdsOf(List<Site> sites) {
		Set<String> durableIds = new Set<String>();
		for (Site one : sites) {
			durableIds.add(String.valueOf(one.Id).left(15));
			durableIds.add(String.valueOf(one.Id));
		}
		return durableIds;
	}

	/** Each Site with its guest user and the secure address its detail gives, if any. */
	@TestVisible
	private static List<SiteInfo> fromRows(List<Site> sites, List<SiteDetail> details) {
		Map<String, String> urlByShortId = new Map<String, String>();
		for (SiteDetail detail : details) {
			urlByShortId.put(detail.DurableId.left(15), detail.SecureUrl);
		}
		List<SiteInfo> result = new List<SiteInfo>();
		for (Site one : sites) {
			SiteInfo info = new SiteInfo();
			info.siteId = one.Id;
			info.name = one.MasterLabel;
			info.guestUserId = one.GuestUserId;
			String url = urlByShortId.get(String.valueOf(one.Id).left(15));
			info.url = url == null ? null : url.removeEnd('/');
			result.add(info);
		}
		return result;
	}

	/** The secure base address of each active Site that has one. */
	public static List<String> activeSiteUrls() {
		List<String> urls = new List<String>();
		for (SiteInfo info : active()) {
			if (info.url != null) {
				urls.add(info.url);
			}
		}
		return urls;
	}

	/**
	 * The public form page's path on a Site: `/FormsPublic`, or with the package prefix once
	 * there is one, as the platform names the page. The platform gives the page's address in
	 * lower case; Site paths ignore case, so the name is written as the page has it.
	 */
	public static String pagePath() {
		String name = Page.FormsPublic.getUrl().substringAfterLast('/');
		return '/' + name.removeEndIgnoreCase('FormsPublic') + 'FormsPublic';
	}
}
