/**
 * The org's own active Salesforce Sites are read as they are, whatever this org has: each with
 * its name and guest user, its address without a trailing slash, and read once a transaction
 * (C-42b; ADR-0184 public forms on a Salesforce Site, decision 9).
 */
@IsTest(testFor='ApexClass:FormsSites')
private class FormsSitesTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	@IsTest
	static void readsTheOrgsActiveSitesOnce() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			Integer expected = [
				SELECT COUNT()
				FROM Site
				WHERE Status = 'Active' AND SiteType = 'Visualforce'
				WITH SYSTEM_MODE
			];

			Test.startTest();
			List<FormsSites.SiteInfo> sites = FormsSites.active();
			Integer queriesAfterFirst = Limits.getQueries();
			List<FormsSites.SiteInfo> again = FormsSites.active();
			List<String> urls = FormsSites.activeSiteUrls();
			Integer queriesAfterAll = Limits.getQueries();
			Test.stopTest();

			Assert.areEqual(Math.min(expected, 50), sites.size(), 'Every active Site, up to 50');
			Assert.areEqual(queriesAfterFirst, queriesAfterAll, 'Read once a transaction');
			Assert.areEqual(sites, again, 'The same answer');
			Integer withAddress = 0;
			for (FormsSites.SiteInfo site : sites) {
				Assert.isNotNull(site.siteId, 'Each Site is named by its id');
				Assert.isNotNull(site.name, 'And its label');
				if (site.url != null) {
					withAddress++;
					Assert.isFalse(site.url.endsWith('/'), 'No trailing slash: ' + site.url);
					Assert.isTrue(urls.contains(site.url), 'Its address is offered for links');
				}
			}
			Assert.areEqual(withAddress, urls.size(), 'Only Sites with an address give one');
		}
	}

	@IsTest
	static void aSiteWithoutAnAddressGivesNoLink() {
		// runs-as: deploying user (pure logic over in-memory Site details, no DML or SOQL)
		FormsSites.SiteInfo withUrl = new FormsSites.SiteInfo();
		withUrl.name = 'Volunteer Forms';
		withUrl.url = 'https://example.my.salesforce-sites.com/forms';
		FormsSites.SiteInfo withoutUrl = new FormsSites.SiteInfo();
		withoutUrl.name = 'Not Published';
		FormsSites.testSites = new List<FormsSites.SiteInfo>{ withUrl, withoutUrl };

		Assert.areEqual(
			new List<String>{ 'https://example.my.salesforce-sites.com/forms' },
			FormsSites.activeSiteUrls()
		);
	}

	@IsTest
	static void eachSiteGetsTheAddressItsDetailGivesByEitherFormOfItsId() {
		// runs-as: deploying user (pure logic over in-memory Site rows, no DML or SOQL)
		Site shortKeyed = site('0DM000000000001', 'Volunteer Forms');
		Site longKeyed = site('0DM000000000002', 'Event Sign-Up');
		Site unpublished = site('0DM000000000003', 'Not Published');
		List<Site> sites = new List<Site>{ shortKeyed, longKeyed, unpublished };
		List<SiteDetail> details = new List<SiteDetail>{
			detail(String.valueOf(shortKeyed.Id).left(15), 'https://one.example.org/forms/'),
			detail(String.valueOf(longKeyed.Id), 'https://two.example.org')
		};

		Set<String> asked = FormsSites.durableIdsOf(sites);
		List<FormsSites.SiteInfo> infos = FormsSites.fromRows(sites, details);

		Assert.areEqual(6, asked.size(), 'Each Site asked by its 15 and its 18 character id');
		Assert.isTrue(asked.contains(String.valueOf(longKeyed.Id)), 'The long form');
		Assert.isTrue(asked.contains(String.valueOf(longKeyed.Id).left(15)), 'The short form');
		Assert.areEqual(3, infos.size(), 'Every Site, in the order given');
		Assert.areEqual('https://one.example.org/forms', infos[0].url, 'No trailing slash');
		Assert.areEqual('Volunteer Forms', infos[0].name, 'Named by its label');
		Assert.areEqual(UserInfo.getUserId(), infos[0].guestUserId, 'With its guest user');
		Assert.areEqual('https://two.example.org', infos[1].url, 'Found by its long id too');
		Assert.isNull(infos[2].url, 'A Site with no detail has no address');
		Assert.areEqual(unpublished.Id, infos[2].siteId, 'But is still listed');
	}

	private static Site site(String shortId, String label) {
		return (Site) JSON.deserialize(
			JSON.serialize(
				new Map<String, Object>{
					'attributes' => new Map<String, Object>{ 'type' => 'Site' },
					'Id' => Id.valueOf(shortId),
					'MasterLabel' => label,
					'GuestUserId' => UserInfo.getUserId()
				}
			),
			Site.class
		);
	}

	private static SiteDetail detail(String durableId, String secureUrl) {
		return (SiteDetail) JSON.deserialize(
			JSON.serialize(
				new Map<String, Object>{
					'attributes' => new Map<String, Object>{ 'type' => 'SiteDetail' },
					'DurableId' => durableId,
					'SecureUrl' => secureUrl
				}
			),
			SiteDetail.class
		);
	}
}
