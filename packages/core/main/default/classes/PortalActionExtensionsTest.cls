/**
 * A module offers a portal action by name, and a module that is missing or fails never stops a
 * portal (ADR-0185 `0185-portal-builder-off-platform-portal-api.md`, decision 9). Core has no
 * module, so extensions are injected by class name.
 */
@IsTest(testFor='ApexClass:PortalActionExtensions')
private class PortalActionExtensionsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private class SignUp implements PortalActionExtension {
		public Set<String> actionNames() {
			return new Set<String>{ 'Volunteers.SignUp' };
		}

		public String run(String actionName, Id personId, Id recordId) {
			return 'Signed up';
		}
	}

	private class Broken implements PortalActionExtension {
		public Set<String> actionNames() {
			throw new System.TypeException('Cannot list');
		}

		public String run(String actionName, Id personId, Id recordId) {
			return null;
		}
	}

	private static void register(Map<String, PortalActionExtension> byName) {
		PortalActionExtensions.EXTENSION_CLASSES.clear();
		PortalActionExtensions.EXTENSION_CLASSES.addAll(byName.keySet());
		PortalActionExtensions.overrides = byName;
	}

	@IsTest
	static void findsTheModuleThatOffersTheAction() {
		System.runAs(TestUsers.admin()) {
			register(
				new Map<String, PortalActionExtension>{
					'BrokenPortalAction' => new Broken(),
					'VolunteersPortalAction' => new SignUp()
				}
			);

			Test.startTest();
			PortalActionExtension found = PortalActionExtensions.forAction('Volunteers.SignUp');
			PortalActionExtension missing = PortalActionExtensions.forAction('Giving.Pay');
			Test.stopTest();

			Assert.isNotNull(found, 'The module offering the action is found past a broken one');
			Assert.areEqual(
				'Signed up',
				found.run('Volunteers.SignUp', null, null),
				'Its run is used'
			);
			Assert.isNull(missing, 'An action no module offers is absent');
		}
	}

	@IsTest
	static void aClassThatIsNotInstalledIsAbsent() {
		System.runAs(TestUsers.admin()) {
			PortalActionExtensions.EXTENSION_CLASSES.clear();
			PortalActionExtensions.EXTENSION_CLASSES.add('NoSuchPortalActionClass');
			PortalActionExtensions.EXTENSION_CLASSES.add('PortalActionExtensions');

			Test.startTest();
			PortalActionExtension found = PortalActionExtensions.forAction('Volunteers.SignUp');
			PortalActionExtension blank = PortalActionExtensions.forAction(' ');
			Test.stopTest();

			Assert.isNull(found, 'A missing class or one of the wrong type offers nothing');
			Assert.isNull(blank, 'A blank action name finds nothing');
		}
	}
}
