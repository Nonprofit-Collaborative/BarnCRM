/**
 * A module publishes pages for its own records through Core, a host is found by name, and a
 * module that fails answers "no page" (ADR-0190 public event pages, decision 1). Core has no
 * module, so extensions are injected by class name, as modules register theirs.
 */
@IsTest(testFor='ApexClass:PublicPageExtensions')
private class PublicPageExtensionsTest {
	private static final String PAGES_CLASS = 'AccountPublicPage';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** Publishes a page for accounts and a list of kind `accounts`. */
	private class Publishing implements PublicPageExtension {
		public String kind() {
			return 'accounts';
		}

		public Boolean handles(Schema.SObjectType recordType) {
			return recordType == Account.SObjectType;
		}

		public Map<String, Object> page(Id recordId) {
			return new Map<String, Object>{
				'title' => 'Spring Gala',
				'signed' => PublicPageExtensions.isSignedRequest()
			};
		}

		public Map<String, Object> listPage() {
			return new Map<String, Object>{ 'title' => 'Our Events' };
		}
	}

	/** Fails on every page, as a module with a bug might. */
	private class Failing implements PublicPageExtension {
		public String kind() {
			return 'accounts';
		}

		public Boolean handles(Schema.SObjectType recordType) {
			return true;
		}

		public Map<String, Object> page(Id recordId) {
			throw new System.TypeException('Cannot tell');
		}

		public Map<String, Object> listPage() {
			throw new System.TypeException('Cannot tell');
		}
	}

	private static void register(PublicPageExtension extension) {
		PublicPageExtensions.EXTENSION_CLASSES.clear();
		PublicPageExtensions.EXTENSION_CLASSES.add(PAGES_CLASS);
		PublicPageExtensions.overrides = new Map<String, PublicPageExtension>{
			PAGES_CLASS => extension
		};
	}

	private static Id accountId() {
		Account record = new Account(Name = 'Spring Gala Venue');
		insert as user record;
		return record.Id;
	}

	@IsTest
	static void theModuleServesItsPageAndList() {
		System.runAs(TestUsers.admin()) {
			register(new Publishing());
			Id recordId = accountId();

			Assert.areEqual('Spring Gala', PublicPageExtensions.page(recordId).get('title'));
			Assert.areEqual('Our Events', PublicPageExtensions.listPage('Accounts').get('title'));
			Assert.isNull(PublicPageExtensions.listPage('volunteers'), 'No such kind');
			Assert.isNull(PublicPageExtensions.listPage(' '), 'No kind asked for');
			Assert.isNull(PublicPageExtensions.page(null), 'No record asked for');
			Assert.isNull(PublicPageExtensions.page(UserInfo.getUserId()), 'Not handled');
		}
	}

	@IsTest
	static void theModuleIsToldWhetherTheHostCheckedASignedClaim() {
		System.runAs(TestUsers.admin()) {
			register(new Publishing());
			Id recordId = accountId();

			Assert.isFalse(
				(Boolean) PublicPageExtensions.page(recordId).get('signed'),
				'Plain address'
			);
			Assert.isTrue(
				(Boolean) PublicPageExtensions.page(recordId, true).get('signed'),
				'Signed'
			);
			Assert.isFalse(PublicPageExtensions.isSignedRequest(), 'Only while the page is built');
		}
	}

	@IsTest
	static void aFailingModuleAnswersNoPage() {
		System.runAs(TestUsers.admin()) {
			register(new Failing());

			Assert.isNull(PublicPageExtensions.page(accountId()), 'No page, no detail');
			Assert.isNull(PublicPageExtensions.listPage('accounts'), 'No list, no detail');
		}
	}

	@IsTest
	static void aModuleThatIsNotInstalledIsAbsent() {
		System.runAs(TestUsers.admin()) {
			PublicPageExtensions.EXTENSION_CLASSES.clear();
			PublicPageExtensions.EXTENSION_CLASSES.add('NoSuchPublicPageClass');
			PublicPageExtensions.EXTENSION_CLASSES.add('PublicPageExtensions');

			Assert.isNull(PublicPageExtensions.page(accountId()), 'Nothing installed');
			PublicPageExtensions.hostForTest = false;
			Assert.isFalse(PublicPageExtensions.hostInstalled(), 'No host');
			PublicPageExtensions.hostForTest = null;
			Assert.isNotNull(PublicPageExtensions.hostInstalled(), 'Resolved by name');
		}
	}
}
