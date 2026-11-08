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
}
