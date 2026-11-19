/**
 * Saved reports and dashboards are Files: private to their owner until shared, shared with
 * people or public groups as Viewer or Collaborator, and changed, shared or deleted only by
 * those Files sharing allows.
 */
@IsTest(testFor='ApexClass:ReportingLibrary')
private class ReportingLibraryTest {
	private static final String DEFINITION = '{"version":1,"object":"Account","title":"Orgs"}';

	@TestSetup
	static void createTestUsers() {
		TestUsers.admin();
		TestUsers.standardUserWith('Owner', new List<String>{ 'Reporting_Staff' });
		TestUsers.standardUserWith('Viewer', new List<String>{ 'Reporting_Staff' });
		TestUsers.standardUserWith('Reader', new List<String>{ 'Reporting_Read_Only' });
	}

	private static User ownerUser() {
		return TestUsers.fromSetup('Owner');
	}

	private static User viewerUser() {
		return TestUsers.fromSetup('Viewer');
	}

	private static Id saveAsOwner() {
		return (Id) ReportingLibrary.save(ReportingLibrary.REPORT, null, 'Orgs', DEFINITION)
			.get('id');
	}

	private static String sharing(String key, Id entryId, String access) {
		return JSON.serialize(
			new Map<String, Object>{
				key => new List<Object>{
					new Map<String, Object>{
						'id' => entryId,
						'name' => 'Someone',
						'access' => access
					}
				}
			}
		);
	}

	@IsTest
	static void anOwnerSavesListsLoadsAndRenamesAReport() {
		System.runAs(ownerUser()) {
			Map<String, Object> context = ReportingLibrary.getContext();
			Assert.isTrue((Boolean) context.get('canSave'), 'Staff may save');
			Id documentId = saveAsOwner();

			List<Map<String, Object>> rows = ReportingLibrary.listSaved();
			Assert.areEqual(1, rows.size(), 'Listed');
			Assert.areEqual(ReportingLibrary.REPORT, rows[0].get('kind'), 'A report');
			Assert.isTrue((Boolean) rows[0].get('mine'), 'Hers');
			Assert.isTrue((Boolean) rows[0].get('canEdit'), 'She may change it');

			Map<String, Object> saved = ReportingLibrary.save(
				ReportingLibrary.REPORT,
				documentId,
				'Organizations',
				'{"version":1,"object":"Account","title":"Organizations"}'
			);
			Assert.areEqual('Organizations', saved.get('title'), 'Renamed by the new version');
			Assert.isTrue(
				String.valueOf(ReportingLibrary.load(documentId).get('definition'))
					.contains('Organizations'),
				'The latest version is loaded'
			);
			Assert.areEqual(1, ReportingLibrary.listSaved().size(), 'Still one report');
		}
	}

	@IsTest
	static void aReportIsPrivateUntilSharedAndAViewerCannotChangeIt() {
		User viewer = viewerUser();
		Id documentId;
		System.runAs(ownerUser()) {
			documentId = saveAsOwner();
		}
		System.runAs(viewer) {
			Assert.areEqual(0, ReportingLibrary.listSaved().size(), 'Private to its owner');
		}
		System.runAs(ownerUser()) {
			ReportingLibrary.share(documentId, sharing('users', viewer.Id, 'view'));
		}
		System.runAs(viewer) {
			List<Map<String, Object>> rows = ReportingLibrary.listSaved();
			Assert.areEqual(1, rows.size(), 'Shared with him');
			Assert.isFalse((Boolean) rows[0].get('canEdit'), 'As a viewer');
			Boolean refused = false;
			try {
				ReportingLibrary.save(ReportingLibrary.REPORT, documentId, 'Mine now', DEFINITION);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Assert.isTrue(refused, 'A viewer cannot save over it');
			refused = false;
			try {
				ReportingLibrary.remove(documentId);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Assert.isTrue(refused, 'Nor delete it');
		}
		System.runAs(ownerUser()) {
			ReportingLibrary.share(documentId, sharing('users', viewer.Id, 'edit'));
		}
		System.runAs(viewer) {
			ReportingLibrary.save(
				ReportingLibrary.REPORT,
				documentId,
				'Orgs',
				'{"version":1,"object":"Account","sharing":{}}'
			);
		}
		System.runAs(ownerUser()) {
			String definition = String.valueOf(ReportingLibrary.load(documentId).get('definition'));
			Assert.isTrue(
				definition.contains(String.valueOf(viewer.Id)),
				'A collaborator\'s save keeps the owner\'s sharing'
			);
			ReportingLibrary.share(documentId, '{}');
		}
		System.runAs(viewer) {
			Assert.areEqual(0, ReportingLibrary.listSaved().size(), 'Unshared again');
		}
	}

	@IsTest
	static void sharingWithAPublicGroupLinksItsPeople() {
		User viewer = viewerUser();
		Group team;
		System.runAs(TestUsers.admin()) {
			team = new Group(Name = 'Reporting Team', Type = 'Regular');
			insert team;
			insert new GroupMember(GroupId = team.Id, UserOrGroupId = viewer.Id);
		}
		Id documentId;
		System.runAs(ownerUser()) {
			documentId = saveAsOwner();
			Boolean teamFound = false;
			for (Map<String, Object> found : ReportingLibrary.findPeople('Reporting Te')) {
				teamFound |= found.get('id') == team.Id && found.get('kind') == 'group';
			}
			Assert.isTrue(teamFound, 'The group is found by name');
			Assert.isTrue(ReportingLibrary.findPeople('R').isEmpty(), 'Two characters at least');
			ReportingLibrary.share(documentId, sharing('groups', team.Id, 'view'));
		}
		System.runAs(viewer) {
			Assert.areEqual(1, ReportingLibrary.listSaved().size(), 'Reached through the group');
		}
	}

	@IsTest
	static void readOnlyPeopleCannotSaveAndBadDefinitionsAreRefused() {
		System.runAs(TestUsers.fromSetup('Reader')) {
			Assert.isFalse((Boolean) ReportingLibrary.getContext().get('canSave'), 'Read only');
			Boolean refused = false;
			try {
				ReportingLibrary.save(ReportingLibrary.REPORT, null, 'Orgs', DEFINITION);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Assert.isTrue(refused, 'Read Only cannot save');
		}
		System.runAs(ownerUser()) {
			List<List<String>> attempts = new List<List<String>>{
				new List<String>{ 'exe', 'Orgs', DEFINITION },
				new List<String>{ ReportingLibrary.REPORT, 'Orgs', 'not json' },
				new List<String>{ ReportingLibrary.REPORT, 'Orgs', '[1, 2]' },
				new List<String>{ ReportingLibrary.REPORT, ' ', DEFINITION }
			};
			Integer refused = 0;
			for (List<String> attempt : attempts) {
				try {
					ReportingLibrary.save(attempt[0], null, attempt[1], attempt[2]);
				} catch (AuraHandledException e) {
					refused++;
				}
			}
			Assert.areEqual(attempts.size(), refused, 'Each is refused');

			Id documentId = saveAsOwner();
			Boolean wrongKind = false;
			try {
				ReportingLibrary.save(ReportingLibrary.DASHBOARD, documentId, 'Orgs', DEFINITION);
			} catch (AuraHandledException e) {
				wrongKind = true;
			}
			Assert.isTrue(wrongKind, 'A report is not saved over as a dashboard');
			ReportingLibrary.remove(documentId);
			Assert.areEqual(0, ReportingLibrary.listSaved().size(), 'Deleted by its owner');
		}
	}
}
