/**
 * The Corporate Hub page and panels: Maria sees what she has to read, what is due and which
 * agreements need a decision; the document panel counts who has read it; a refusal reaches the
 * person in their own words.
 */
@IsTest(testFor='ApexClass:CorporateHubController')
private class CorporateHubControllerTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static Hub_Document__c policy() {
		Hub_Document__c document = new Hub_Document__c(
			Name = 'Conflict of Interest',
			Status__c = 'Active',
			Version__c = 1,
			Requires_Acknowledgment__c = true
		);
		insert document;
		return document;
	}

	@IsTest
	static void theHomePageListsRequestsDueObligationsAndAgreements() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Hub_Document__c document = policy();
			CorporateHubController.requestAcknowledgments(document.Id, null);
			insert new Compliance_Obligation__c(
				Name = 'Annual report',
				Status__c = 'Active',
				Due_Date__c = Date.today().addDays(10)
			);
			insert new Compliance_Obligation__c(
				Name = 'Far away',
				Status__c = 'Active',
				Due_Date__c = Date.today().addDays(200)
			);
			insert new Agreement__c(
				Name = 'Office lease',
				Status__c = 'Active',
				Start_Date__c = Date.today().addYears(-1),
				End_Date__c = Date.today().addDays(60),
				Notice_Days__c = 30
			);

			CorporateHubController.Home home = CorporateHubController.getHome();

			Assert.isTrue(home.canManage, 'Maria manages the hub');
			Assert.areEqual(1, home.requests.size(), 'Her own request');
			Assert.areEqual(document.Id, home.requests[0].recordId, 'Opens the policy');
			Assert.areEqual(1, home.obligations.size(), 'Only the one due within 60 days');
			Assert.areEqual('Annual report', home.obligations[0].name, 'The annual report');
			Assert.areEqual(1, home.agreements.size(), 'The lease');
			Assert.areEqual(Date.today().addDays(30), home.agreements[0].due, 'By its notice date');
		}
	}

	@IsTest
	static void theDocumentPanelCountsWhoHasReadIt() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Hub_Document__c document = policy();
			Integer asked = CorporateHubController.requestAcknowledgments(document.Id, null);
			CorporateHubController.DocumentStatus before = CorporateHubController.getDocumentStatus(
				document.Id
			);
			CorporateHubController.acknowledge(CorporateHubController.getHome().requests[0].id);
			CorporateHubController.DocumentStatus after = CorporateHubController.getDocumentStatus(
				document.Id
			);

			Assert.areEqual(1, before.version, 'Version 1');
			Assert.isTrue(before.needsAcknowledgment, 'Needs reading');
			Assert.isTrue(before.canEdit, 'Maria can edit it');
			Assert.areEqual(asked, before.outstanding, 'Everyone asked is outstanding');
			Assert.areEqual(asked, before.people.size(), 'One line each');
			Assert.areEqual(1, after.acknowledged, 'Maria has read it');
			Assert.areEqual(asked - 1, after.outstanding, 'The rest have not');

			CorporateHubController.markReviewed(document.Id);
			CorporateHubController.publishNewVersion(document.Id);
			Assert.areEqual(
				2,
				CorporateHubController.getDocumentStatus(document.Id).version,
				'Version 2'
			);
			CorporateHubController.retire(document.Id);
			Assert.areEqual(
				'Retired',
				CorporateHubController.getDocumentStatus(document.Id).status,
				'Retired'
			);
		}
	}

	@IsTest
	static void completingACycleAndAddingTemplatesGoThroughThePage() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Compliance_Obligation__c row = new Compliance_Obligation__c(
				Name = 'Insurance',
				Status__c = 'Active',
				Recurrence__c = 'Yearly',
				Due_Date__c = Date.today()
			);
			insert row;

			Id cycleId = CorporateHubController.completeCycle(row.Id, null, 'Done', 'Renewed');
			Integer added = CorporateHubController.addMissingTemplates();

			Assert.isNotNull(cycleId, 'A cycle to attach evidence to');
			Assert.isTrue(added > 0, 'The shipped templates');
		}
	}

	@IsTest
	static void aRefusalIsShownInItsOwnWordsAndAnythingElseIsLogged() {
		User sam = TestUsers.standardUserWith(
			'Sam',
			new List<String>{ 'BarnCRM_Staff', 'Corporate_Hub_Staff' }
		);
		System.runAs(sam) {
			try {
				CorporateHubController.addMissingTemplates();
				Assert.fail('Staff cannot add templates');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('CorporateHub', 'CorporateHub_Policy_NoPermission'),
					expected.getMessage(),
					'In its own words'
				);
			}
		}
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Hub_Document__c gone = policy();
			delete gone;
			Id missing = gone.Id;
			try {
				CorporateHubController.getDocumentStatus(missing);
				Assert.fail('No such document');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('CorporateHub', 'CorporateHub_Error_Generic'),
					expected.getMessage(),
					'One message'
				);
			}
		}
		Test.getEventBus().deliver();
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM Error_Log__c
				WHERE Context__c = 'CorporateHubController'
				WITH SYSTEM_MODE
			],
			'Logged'
		);
	}
}
