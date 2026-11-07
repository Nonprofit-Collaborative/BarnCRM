/**
 * Portals, people and signed-in sessions for Portal Builder's tests. Test only.
 *
 * The sample template is the one `portal-client/templates/sample.json` holds: a My Details page
 * on the person and a My Roles page of their current affiliations, plus one test-only module
 * action (`Test.Thanks`) the shipped sample leaves out.
 */
@IsTest
public class PortalTestData {
	public static final String KEY = 'sample';

	/** The sample template as JSON. */
	public static String template() {
		return JSON.serialize(
			new Map<String, Object>{
				'schemaVersion' => 1,
				'key' => 'sample',
				'title' => 'My Account',
				'pages' => new List<Object>{
					new Map<String, Object>{
						'key' => 'profile',
						'title' => 'My Details',
						'kind' => 'person',
						'fields' => new List<Object>{
							new Map<String, Object>{ 'field' => 'FirstName' },
							new Map<String, Object>{ 'field' => 'LastName' },
							new Map<String, Object>{
								'field' => 'MobilePhone',
								'label' => 'Mobile',
								'edit' => true
							},
							new Map<String, Object>{ 'field' => 'Description', 'edit' => true }
						},
						'actions' => new List<Object>{ 'update' }
					},
					new Map<String, Object>{
						'key' => 'roles',
						'title' => 'My Roles',
						'kind' => 'related',
						'object' => 'Affiliation__c',
						'personField' => 'Contact__c',
						'fields' => new List<Object>{
							new Map<String, Object>{
								'field' => 'Organization__r.Name',
								'label' => 'Organization'
							},
							new Map<String, Object>{
								'field' => 'Role__c',
								'edit' => true,
								'required' => true
							},
							new Map<String, Object>{ 'field' => 'Status__c' }
						},
						'where' => new List<Object>{
							new Map<String, Object>{
								'field' => 'Status__c',
								'op' => 'equals',
								'value' => 'Current'
							}
						},
						'orderBy' => 'Role__c ASC',
						'actions' => new List<Object>{
							'update',
							new Map<String, Object>{
								'extension' => 'Test.Thanks',
								'label' => 'Say Thanks'
							}
						}
					}
				}
			}
		);
	}

	/** Turns Portal Sign-In on, with the shipped limits. */
	public static void enable() {
		Portal_Settings__c settings = Portal_Settings__c.getOrgDefaults();
		settings.Enabled__c = true;
		upsert settings;
	}

	/** An active portal with the sample template. */
	public static Portal__c portal(String accessMode, String secondFactor) {
		Portal__c portal = new Portal__c(
			Name = 'Sample Portal',
			Key__c = KEY,
			Status__c = 'Active',
			Access_Mode__c = accessMode,
			Second_Factor__c = secondFactor,
			Template__c = template()
		);
		insert portal;
		return portal;
	}

	/** A person with this email. */
	public static Contact person(String lastName, String email) {
		Contact person = new Contact(FirstName = 'Pat', LastName = lastName, Email = email);
		// Two people may share an email in a test; an org's duplicate rule must not stop that.
		Database.DMLOptions options = new Database.DMLOptions();
		options.DuplicateRuleHeader.allowSave = true;
		Database.insert(person, options, AccessLevel.USER_MODE);
		return person;
	}

	/** An active access for the person. */
	public static Portal_Access__c access(Portal__c portal, Contact person) {
		Portal_Access__c access = new Portal_Access__c(
			Portal__c = portal.Id,
			Person__c = person.Id,
			Status__c = 'Active'
		);
		insert access;
		return access;
	}

	/** Signs in with the emailed code (no second factor) and returns the session token. */
	public static String signIn(String email) {
		String challenge = PortalAuth.start(KEY, email);
		Map<String, Object> result = PortalAuth.verifyCode(challenge, PortalAuth.lastCodeForTest);
		return (String) result.get('session');
	}
}
