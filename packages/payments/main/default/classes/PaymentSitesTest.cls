/**
 * PaymentSites (ADR-0201 payments module, decision 4): each active Site is reported with its
 * name and guest user, and a Site with no secure address has none. A test cannot create a
 * Site, so the Sites are built in memory.
 */
@IsTest(testFor='ApexClass:PaymentSites')
private class PaymentSitesTest {
	// runs-as: deploying user (Site and SiteDetail are read in system mode; no DML)

	private static Site site(String id, String label, Id guestUserId) {
		return (Site) JSON.deserialize(
			JSON.serialize(
				new Map<String, Object>{
					'Id' => id,
					'MasterLabel' => label,
					'GuestUserId' => guestUserId
				}
			),
			Site.class
		);
	}

	@IsTest
	static void eachSiteIsReportedWithItsGuestUser() {
		List<Site> sites = new List<Site>{
			site('0DM000000000001AAA', 'Donations', UserInfo.getUserId()),
			site('0DM000000000002AAA', 'Events', null)
		};

		Test.startTest();
		List<PaymentSites.SiteInfo> infos = PaymentSites.describe(sites);
		Test.stopTest();

		Assert.areEqual(2, infos.size(), 'Every Site is reported');
		Assert.areEqual('Donations', infos[0].name, 'The Site keeps its name');
		Assert.areEqual(
			UserInfo.getUserId(),
			infos[0].guestUserId,
			'The Site keeps its guest user'
		);
		Assert.isNull(infos[0].url, 'A Site with no secure address has none');
		Assert.isNull(infos[1].guestUserId, 'A Site with no guest user has none');
	}

	@IsTest
	static void noSitesMeansNothingReported() {
		Assert.isTrue(
			PaymentSites.describe(new List<Site>()).isEmpty(),
			'No Sites, nothing reported'
		);
	}

	@IsTest
	static void guestUsersComeFromTheReportedSites() {
		PaymentSites.SiteInfo withGuest = new PaymentSites.SiteInfo();
		withGuest.guestUserId = UserInfo.getUserId();
		PaymentSites.testSites = new List<PaymentSites.SiteInfo>{
			withGuest,
			new PaymentSites.SiteInfo()
		};

		Set<Id> ids = PaymentSites.guestUserIds();

		Assert.areEqual(
			new Set<Id>{ UserInfo.getUserId() },
			ids,
			'Only Sites with a guest user count'
		);
	}

	@IsTest
	static void activeReadsTheOrgsSitesOnce() {
		List<PaymentSites.SiteInfo> first = PaymentSites.active();
		List<PaymentSites.SiteInfo> second = PaymentSites.active();

		Assert.areEqual(first, second, 'The second call returns the cached list');
	}
}
