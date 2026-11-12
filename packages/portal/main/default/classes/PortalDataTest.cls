/**
 * A signed-in person sees and changes only their own records, and only what the template
 * allows (canonical model R-PB3); a module's action runs through Core's seam.
 */
@IsTest(testFor='ApexClass:PortalData')
private class PortalDataTest {
	private static final String EMAIL = 'pat.zzdata@example.org';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Portal_Admin');
	}

	private class Fixture {
		Contact pat;
		Contact other;
		Affiliation__c current;
		Affiliation__c former;
		Affiliation__c othersRole;
		PortalAuth.Session session;
	}

	private static Fixture fixture() {
		PortalTestData.enable();
		Portal__c portal = PortalTestData.portal('Invited', 'Off');
		Fixture f = new Fixture();
		f.pat = PortalTestData.person('Zzdata', EMAIL);
		f.other = PortalTestData.person('Zzother', 'other.zzdata@example.org');
		PortalTestData.access(portal, f.pat);
		Account org = new Account(Name = 'Zzdata Foundation');
		insert org;
		f.current = new Affiliation__c(
			Contact__c = f.pat.Id,
			Organization__c = org.Id,
			Role__c = 'Volunteer',
			Status__c = 'Current'
		);
		f.former = new Affiliation__c(
			Contact__c = f.pat.Id,
			Organization__c = org.Id,
			Role__c = 'Intern',
			Status__c = 'Former'
		);
		f.othersRole = new Affiliation__c(
			Contact__c = f.other.Id,
			Organization__c = org.Id,
			Role__c = 'Chair',
			Status__c = 'Current'
		);
		insert new List<Affiliation__c>{ f.current, f.former, f.othersRole };
		f.session = PortalAuth.resolve(PortalTestData.signIn(EMAIL));
		return f;
	}

	private static String refusal(
		PortalAuth.Session session,
		String page,
		String recordId,
		Map<String, Object> values
	) {
		try {
			PortalData.save(session, page, recordId, values);
		} catch (PortalAuth.RefusalException refused) {
			return refused.getMessage();
		}
		return null;
	}

	@IsTest
	static void showsThePersonTheirPagesAndOwnRecords() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Fixture f = fixture();

			Test.startTest();
			Map<String, Object> menu = PortalData.describe(f.session);
			Map<String, Object> roles = PortalData.read(f.session, 'roles');
			Map<String, Object> profile = PortalData.read(f.session, 'profile');
			Test.stopTest();

			Assert.areEqual('My Account', menu.get('title'), 'The template title');
			Assert.areEqual('Pat', menu.get('firstName'), 'Greets the person');
			Assert.areEqual(2, ((List<Object>) menu.get('pages')).size(), 'Two pages');
			List<Object> rows = (List<Object>) roles.get('records');
			Assert.areEqual(
				1,
				rows.size(),
				'Only their current role, not the former one or anyone else'
			);
			Map<String, Object> values = (Map<String, Object>) ((Map<String, Object>) rows[0])
				.get('values');
			Assert.areEqual(
				'Zzdata Foundation',
				values.get('Organization__r.Name'),
				'A parent field is read'
			);
			List<Object> people = (List<Object>) profile.get('records');
			Assert.areEqual(
				f.pat.Id,
				((Map<String, Object>) people[0]).get('id'),
				'Their own record'
			);
			Assert.isNull(menu.get('brand'), 'No brand while brands are off');
		}
	}

	@IsTest
	static void aBrandedPortalSendsItsBrandToTheClient() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Fixture f = fixture();
			BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
			settings.Brand_Management__c = true;
			upsert settings;
			Brand__c thrift = new Brand__c(
				Name = 'Barn Thrift',
				Primary_Color__c = '#1B5E20',
				City__c = 'Shelbyville'
			);
			insert thrift;
			f.session.portal.Brand__c = thrift.Id;

			Test.startTest();
			Map<String, Object> brand = (Map<String, Object>) PortalData.describe(f.session)
				.get('brand');
			Test.stopTest();

			Assert.areEqual('Barn Thrift', brand.get('name'), 'The brand name');
			Assert.areEqual('#1B5E20', brand.get('primaryColor'), 'The brand color');
			Assert.areEqual(
				new List<String>{ 'Shelbyville' },
				brand.get('address'),
				'The address lines'
			);
		}
	}

	@IsTest
	static void savesOnlyEditableFieldsOnTheirOwnRecords() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Fixture f = fixture();

			Test.startTest();
			PortalData.save(
				f.session,
				'profile',
				f.pat.Id,
				new Map<String, Object>{ 'MobilePhone' => '555-0100' }
			);
			PortalData.save(
				f.session,
				'roles',
				f.current.Id,
				new Map<String, Object>{ 'Role__c' => 'Team Captain' }
			);
			List<String> refusals = new List<String>{
				refusal(
					f.session,
					'profile',
					f.pat.Id,
					new Map<String, Object>{ 'FirstName' => 'Mallory' }
				),
				refusal(
					f.session,
					'roles',
					f.othersRole.Id,
					new Map<String, Object>{ 'Role__c' => 'Mine' }
				),
				refusal(
					f.session,
					'roles',
					f.former.Id,
					new Map<String, Object>{ 'Role__c' => 'Back' }
				),
				refusal(f.session, 'roles', null, new Map<String, Object>{ 'Role__c' => 'New' }),
				refusal(
					f.session,
					'roles',
					f.current.Id,
					new Map<String, Object>{ 'Role__c' => '' }
				),
				refusal(
					f.session,
					'profile',
					f.other.Id,
					new Map<String, Object>{ 'MobilePhone' => '1' }
				),
				refusal(f.session, 'nope', f.pat.Id, new Map<String, Object>())
			};
			Test.stopTest();

			Assert.areEqual(
				'555-0100',
				[SELECT MobilePhone FROM Contact WHERE Id = :f.pat.Id].MobilePhone,
				'Saved'
			);
			Assert.areEqual(
				'Team Captain',
				[SELECT Role__c FROM Affiliation__c WHERE Id = :f.current.Id].Role__c,
				'Saved'
			);
			Assert.areEqual('not_allowed', refusals[0], 'A read-only field is refused');
			Assert.areEqual('not_found', refusals[1], 'Someone else\'s record is not there');
			Assert.areEqual(
				'not_found',
				refusals[2],
				'A record outside the page tests is not there'
			);
			Assert.areEqual('not_allowed', refusals[3], 'The page does not create');
			Assert.areEqual('required_missing', refusals[4], 'A required field stays filled');
			Assert.areEqual('not_found', refusals[5], 'Another person is not their record');
			Assert.areEqual('not_found', refusals[6], 'An unknown page');
			Assert.areEqual(
				'Chair',
				[SELECT Role__c FROM Affiliation__c WHERE Id = :f.othersRole.Id].Role__c,
				'Untouched'
			);
		}
	}

	@IsTest
	static void runsAModuleActionThroughCoresSeam() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Fixture f = fixture();
			PortalTestModule.register();

			Test.startTest();
			String message = PortalData.runAction(f.session, 'roles', f.current.Id, 'Test.Thanks');
			String refusedOnOthers;
			try {
				PortalData.runAction(f.session, 'roles', f.othersRole.Id, 'Test.Thanks');
			} catch (PortalAuth.RefusalException refused) {
				refusedOnOthers = refused.getMessage();
			}
			PortalTestModule.fail = true;
			String failed;
			try {
				PortalData.runAction(f.session, 'roles', f.current.Id, 'Test.Thanks');
			} catch (PortalAuth.RefusalException refused) {
				failed = refused.getMessage();
			}
			Test.stopTest();

			Assert.areEqual('Thanks sent', message, 'The module answered');
			Assert.areEqual(1, PortalTestModule.ran.size(), 'Run once, for their own record');
			Assert.isTrue(
				PortalTestModule.ran[0].contains(String.valueOf(f.pat.Id)),
				'For the verified person'
			);
			Assert.areEqual('not_found', refusedOnOthers, 'Never on someone else\'s record');
			Assert.areEqual(
				'action_failed',
				failed,
				'A module refusal is reported, not its detail'
			);
		}
	}

	@IsTest
	static void aBrokenTemplateClosesThePortal() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Fixture f = fixture();
			f.session.portal.Template__c = '{"schemaVersion": 1, "pages": [{"key": "x", "kind": "related", "object": "Account"}]}';

			Test.startTest();
			String answer;
			try {
				PortalData.describe(f.session);
			} catch (PortalAuth.RefusalException refused) {
				answer = refused.getMessage();
			}
			Test.stopTest();

			Assert.areEqual('portal_unavailable', answer, 'Refused whole');
		}
	}

	@IsTest
	static void coercesValuesToTheFieldType() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Test.startTest();
			Object day = PortalData.coerce(
				Schema.SObjectType.Contact.fields.Birthdate,
				'2001-02-03'
			);
			Object off = PortalData.coerce(
				Schema.SObjectType.Affiliation__c.fields.Is_Primary__c,
				null
			);
			Object staff = PortalData.coerce(
				Schema.SObjectType.Account.fields.NumberOfEmployees,
				'12'
			);
			String bad;
			try {
				PortalData.coerce(Schema.SObjectType.Affiliation__c.fields.Status__c, 'Invented');
			} catch (PortalAuth.RefusalException refused) {
				bad = refused.getMessage();
			}
			String fraction;
			try {
				PortalData.coerce(Schema.SObjectType.Account.fields.NumberOfEmployees, '1.5');
			} catch (PortalAuth.RefusalException refused) {
				fraction = refused.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(Date.newInstance(2001, 2, 3), day, 'A date');
			Assert.areEqual(false, off, 'A blank checkbox is false');
			Assert.isTrue(staff instanceof Integer, 'A whole-number field takes an Integer');
			Assert.areEqual(12, staff, 'Its value');
			Assert.areEqual('invalid_value', bad, 'A picklist value must be one of its own');
			Assert.areEqual('invalid_value', fraction, 'A whole-number field takes no fraction');
		}
	}
}
