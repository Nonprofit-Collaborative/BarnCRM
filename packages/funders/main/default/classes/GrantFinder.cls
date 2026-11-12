/**
 * The Grant Finder (F-09, canonical model R-GN11, ADR-0200 funders grant finder and grant
 * management): searches open federal funding listings on the public Grants.gov search API, which
 * needs no account or key, and saves one as a Prospect grant.
 *
 * The endpoint is the packaged Remote Site Setting `BarnCRM_Grants_Gov`. Only the words searched
 * leave the org. Saving runs as the person.
 */
public with sharing class GrantFinder {
	public static final String ENDPOINT = 'https://api.grants.gov/v1/api/search2';
	/** A listing's page on Grants.gov, followed by its id. */
	public static final String LISTING_PAGE = 'https://www.grants.gov/search-results-detail/';
	public static final Integer ROWS = 25;
	/** Named apart from `search`'s `statuses` parameter: Apex names ignore case, so the two collided. */
	private static final Set<String> KNOWN_STATUSES = new Set<String>{ 'posted', 'forecasted' };
	private static final Pattern ALN_FORMAT = Pattern.compile('^\\d{2}\\.[0-9A-Z]{3}$');
	private static final Pattern US_DATE = Pattern.compile('^(\\d{2})/(\\d{2})/(\\d{4})$');

	/** Thrown with a message a person can act on. */
	public class GrantFinderException extends Exception {
	}

	/** One funding listing, as the tab shows it. */
	public class Listing {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String listingNumber;
		@AuraEnabled
		public String title;
		@AuraEnabled
		public String agency;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Date openDate;
		@AuraEnabled
		public Date closeDate;
		@AuraEnabled
		public String assistanceListing;
		@AuraEnabled
		public String url;
		/** The grant it was saved to, if any the person can see. */
		@AuraEnabled
		public Id grantId;
	}

	/**
	 * Searches Grants.gov.
	 *
	 * @param keyword the words to search for
	 * @param statuses posted, forecasted or both; anything else is ignored
	 * @return up to ROWS listings, each marked with its grant when already saved
	 */
	public static List<Listing> search(String keyword, List<String> statuses) {
		List<String> wanted = new List<String>();
		for (String status : statuses == null ? new List<String>() : statuses) {
			if (status != null && KNOWN_STATUSES.contains(status.toLowerCase())) {
				wanted.add(status.toLowerCase());
			}
		}
		if (wanted.isEmpty()) {
			wanted.add('posted');
		}
		HttpRequest request = new HttpRequest();
		request.setEndpoint(ENDPOINT);
		request.setMethod('POST');
		request.setHeader('Content-Type', 'application/json');
		request.setTimeout(20000);
		request.setBody(
			JSON.serialize(
				new Map<String, Object>{
					'keyword' => keyword == null ? '' : keyword.trim().left(200),
					'oppStatuses' => String.join(wanted, '|'),
					'rows' => ROWS
				}
			)
		);
		HttpResponse response = new Http().send(request);
		if (response.getStatusCode() != 200) {
			throw new GrantFinderException('Grants.gov answered ' + response.getStatusCode());
		}
		Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
			response.getBody()
		);
		Map<String, Object> data = (Map<String, Object>) body.get('data');
		List<Object> hits = data == null ? null : (List<Object>) data.get('oppHits');
		List<Listing> listings = new List<Listing>();
		for (Object hit : hits == null ? new List<Object>() : hits) {
			listings.add(toListing((Map<String, Object>) hit));
		}
		markSaved(listings);
		return listings;
	}

	private static Listing toListing(Map<String, Object> hit) {
		Listing listing = new Listing();
		listing.id = text(hit.get('id'));
		listing.listingNumber = text(hit.get('number'));
		listing.title = text(hit.get('title'));
		listing.agency = firstText(hit, new List<String>{ 'agency', 'agencyName', 'agencyCode' });
		listing.status = text(hit.get('oppStatus'));
		listing.openDate = usDate(text(hit.get('openDate')));
		listing.closeDate = usDate(text(hit.get('closeDate')));
		Object numbers = hit.containsKey('alnist') ? hit.get('alnist') : hit.get('cfdaList');
		if (numbers instanceof List<Object> && !((List<Object>) numbers).isEmpty()) {
			listing.assistanceListing = text(((List<Object>) numbers)[0]);
		}
		listing.url = String.isBlank(listing.id) ? null : LISTING_PAGE + listing.id;
		return listing;
	}

	@TestVisible
	private static void markSaved(List<Listing> listings) {
		Map<String, Listing> byUrl = new Map<String, Listing>();
		for (Listing listing : listings) {
			if (listing.url != null) {
				byUrl.put(listing.url, listing);
			}
		}
		if (byUrl.isEmpty()) {
			return;
		}
		for (Grant__c grant : [
			SELECT Id, Opportunity_Url__c
			FROM Grant__c
			WHERE Opportunity_Url__c IN :byUrl.keySet()
			WITH USER_MODE
			LIMIT 200
		]) {
			byUrl.get(grant.Opportunity_Url__c).grantId = grant.Id;
		}
	}

	/**
	 * Save to Pipeline (R-GN11), as the person: a Prospect grant from the listing, to the
	 * organization of the agency's exact name, made when there is none. A listing already saved
	 * returns its grant.
	 */
	public static Id save(Listing listing) {
		if (listing == null || String.isBlank(listing.title) || String.isBlank(listing.agency)) {
			throw new GrantFinderException('A listing needs a title and an agency.');
		}
		String url = listing.url != null && listing.url.startsWith(LISTING_PAGE)
			? listing.url
			: null;
		if (url != null) {
			for (Grant__c saved : [
				SELECT Id
				FROM Grant__c
				WHERE Opportunity_Url__c = :url
				WITH USER_MODE
				LIMIT 1
			]) {
				return saved.Id;
			}
		}
		String aln = listing.assistanceListing == null ? '' : listing.assistanceListing.trim();
		Grant__c grant = new Grant__c(
			Name = listing.title.trim().left(80),
			Funder__c = funderFor(listing.agency.trim().left(255)),
			Stage__c = GrantService.STAGE_PROSPECT,
			Application_Deadline__c = listing.closeDate,
			Funding_Source__c = 'Federal',
			Federal_Agency__c = listing.agency.trim().left(255),
			Assistance_Listing_Number__c = ALN_FORMAT.matcher(aln).matches() ? aln : null,
			Opportunity_Url__c = url
		);
		insert as user grant;
		return grant.Id;
	}

	private static Id funderFor(String agency) {
		Id organizationType = AccountKinds.organizationRecordTypeId();
		for (Account existing : [
			SELECT Id
			FROM Account
			WHERE Name = :agency AND RecordTypeId = :organizationType
			WITH USER_MODE
			ORDER BY CreatedDate
			LIMIT 1
		]) {
			return existing.Id;
		}
		Account organization = new Account(Name = agency);
		if (organizationType != null) {
			organization.RecordTypeId = organizationType;
		}
		insert as user organization;
		return organization.Id;
	}

	private static String text(Object value) {
		return value == null ? null : String.valueOf(value);
	}

	private static String firstText(Map<String, Object> hit, List<String> keys) {
		for (String key : keys) {
			String value = text(hit.get(key));
			if (String.isNotBlank(value)) {
				return value;
			}
		}
		return null;
	}

	/** Grants.gov writes dates as MM/DD/YYYY; anything else reads as no date. */
	@TestVisible
	private static Date usDate(String value) {
		Matcher parts = US_DATE.matcher(value == null ? '' : value.trim());
		if (!parts.matches()) {
			return null;
		}
		return Date.newInstance(
			Integer.valueOf(parts.group(3)),
			Integer.valueOf(parts.group(1)),
			Integer.valueOf(parts.group(2))
		);
	}
}
