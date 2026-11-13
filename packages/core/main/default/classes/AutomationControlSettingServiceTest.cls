/**
 * The Automation page manages the BarnCRM Automation Control rows, an org's own flows and Catch
 * Up Now (canonical model R-A8, ADR-0165 dispatcher errors and Automation Control 2.6 to 2.8).
 */
@IsTest(
	testFor='ApexClass:AutomationControlSettingService, ApexClass:AutomationControlController, ApexClass:AutomationSettingsWriter'
)
private class AutomationControlSettingServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer changesNamed(String prefix) {
		String pattern = prefix + '%';
		return [
			SELECT COUNT()
			FROM Setting_Change__c
			WHERE Setting_Name__c LIKE :pattern
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theWholeOrganizationRowIsAlwaysShownAndPausesEveryone() {
		System.runAs(TestUsers.admin()) {
			Id orgId = UserInfo.getOrganizationId();

			Test.startTest();
			List<AutomationControlSettingService.ControlRow> before = AutomationControlSettingService.rows();
			AutomationControlSettingService.save(orgId, true, false);
			List<AutomationControlSettingService.ControlRow> after = AutomationControlSettingService.rows();
			Test.stopTest();

			Assert.areEqual(1, before.size(), 'Only the organization row before anything is saved');
			Assert.areEqual(
				AutomationControlSettingService.LEVEL_ORGANIZATION,
				before[0].level,
				'It is the organization row'
			);
			Assert.isFalse(before[0].pauseAll, 'Both boxes show off by default');
			Assert.isFalse(before[0].bypass, 'Both boxes show off by default');
			Assert.isTrue(after[0].pauseAll, 'Pause All saved for the whole organization');
			Assert.isTrue(
				AutomationControlSettingService.pausedForEveryone(),
				'Paused for everyone'
			);
			Assert.areEqual(1, changesNamed('Automation Control:'), 'The change is recorded');
			Assert.areEqual(
				1,
				changesNamed('Automation Control: Whole Organization'),
				'The log names the org row once, without the level word'
			);
		}
	}

	@IsTest
	static void removingAnOwnerThatIsGoneDeletesNothingAndRefusesNothing() {
		System.runAs(TestUsers.admin()) {
			// A well-formed User id with no record behind it, as a deleted user leaves.
			String gone = String.valueOf(UserInfo.getUserId()).substring(0, 12) + 'ZZZ';
			Exception refused;

			Test.startTest();
			try {
				AutomationControlSettingService.remove(gone);
			} catch (Exception e) {
				refused = e;
			}
			Test.stopTest();

			Assert.isNull(refused, 'A remove of a missing owner is not an error');
			Assert.areEqual(0, changesNamed('Automation Control:'), 'And nothing was changed');
		}
	}

	@IsTest
	static void aProfileRowIsAddedWithBypassSavedAndRemoved() {
		System.runAs(TestUsers.admin()) {
			Id profileId = UserInfo.getProfileId();

			Test.startTest();
			AutomationControlSettingService.add(profileId);
			BarnCRM_Automation_Control__c added = BarnCRM_Automation_Control__c.getValues(
				profileId
			);
			List<AutomationControlSettingService.ControlRow> listed = AutomationControlSettingService.rows();
			AutomationControlSettingService.save(profileId, true, false);
			BarnCRM_Automation_Control__c saved = BarnCRM_Automation_Control__c.getValues(
				profileId
			);
			AutomationControlSettingService.remove(profileId);
			Test.stopTest();

			Assert.isTrue(added.Bypass__c, 'A new row starts with Bypass on');
			Assert.isFalse(added.Pause_All__c, 'and Pause All off');
			Assert.areEqual(2, listed.size(), 'The organization row and the profile');
			Assert.areEqual(
				AutomationControlSettingService.LEVEL_PROFILE,
				listed[1].level,
				'The profile row follows the organization'
			);
			Assert.isNotNull(listed[1].ownerName, 'The profile is named');
			Assert.isTrue(saved.Pause_All__c && !saved.Bypass__c, 'Both boxes saved');
			Assert.areEqual(
				1,
				AutomationControlSettingService.rows().size(),
				'Removed: only the organization row is left'
			);
			Assert.areEqual(3, changesNamed('Automation Control:'), 'Each change is recorded');
		}
	}

	@IsTest
	static void aUserRowAppliesToThatUser() {
		System.runAs(TestUsers.admin()) {
			Id userId = UserInfo.getUserId();

			Test.startTest();
			AutomationControlSettingService.add(userId);
			Test.stopTest();

			List<AutomationControlSettingService.ControlRow> listed = AutomationControlSettingService.rows();
			Assert.areEqual(
				AutomationControlSettingService.LEVEL_USER,
				listed[listed.size() - 1].level,
				'Users come last'
			);
			Assert.isTrue(AutomationControl.isOffForRunningUser(), 'The user now bypasses');
		}
	}

	@IsTest
	static void theOrganizationRowCannotBeRemovedAndAnUnknownOwnerIsRefused() {
		System.runAs(TestUsers.admin()) {
			Account notAnOwner = TestDataFactory.organization(new Account(Name = 'Not a profile'));
			insert as user notAnOwner;
			List<String> messages = new List<String>();

			Test.startTest();
			for (
				String owner : new List<String>{
					UserInfo.getOrganizationId(),
					notAnOwner.Id,
					'junk'
				}
			) {
				try {
					if (owner == UserInfo.getOrganizationId()) {
						AutomationControlSettingService.remove(owner);
					} else {
						AutomationControlSettingService.save(owner, false, true);
					}
				} catch (AutomationControl.AutomationControlException e) {
					messages.add(e.getMessage());
				}
			}
			Test.stopTest();

			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Core', 'Core_AutomationControl_OrgRowStays'),
					BarnHelp.text('Core', 'Core_AutomationControl_OwnerGone'),
					BarnHelp.text('Core', 'Core_AutomationControl_OwnerGone')
				},
				messages,
				'Each refusal says what to do'
			);
		}
	}

	@IsTest
	static void someoneWithoutManageSettingsCannotChangeAnything() {
		User staff = TestUsers.standardUserWith(
			'AutoControlStaff',
			new List<String>{ 'BarnCRM_Staff' }
		);
		System.runAs(staff) {
			Integer refused = 0;

			Test.startTest();
			try {
				AutomationControlSettingService.save(UserInfo.getOrganizationId(), true, false);
			} catch (AutomationControl.AutomationControlException e) {
				refused++;
			}
			try {
				AutomationControlSettingService.catchUpNow();
			} catch (AutomationControl.AutomationControlException e) {
				refused++;
			}
			try {
				AutomationControlSettingService.addFlow('Any_Flow');
			} catch (AutomationControl.AutomationControlException e) {
				refused++;
			}
			Test.stopTest();

			Assert.areEqual(3, refused, 'Every write needs Manage BarnCRM Settings');
			Assert.isFalse(AutomationControl.isPausedForEveryone(), 'Nothing was saved');
		}
	}

	@IsTest
	static void anOwnFlowIsListedAndRemovedButNotABarnCrmAutomation() {
		System.runAs(TestUsers.admin()) {
			List<SObject> anyFlow = Database.query(
				'SELECT ApiName FROM FlowDefinitionView WHERE NamespacePrefix = null LIMIT 1',
				AccessLevel.SYSTEM_MODE
			);
			Automation_Setting__c shipped = new Automation_Setting__c(
				Name = 'Shipped',
				Automation_Name__c = 'Flow:Shipped_Default',
				Enabled__c = true,
				Is_Package_Default__c = true
			);
			insert as system shipped;
			String notFound;
			String notOwn;

			Test.startTest();
			try {
				AutomationControlSettingService.addFlow('No_Such_Flow_Here');
			} catch (AutomationControl.AutomationControlException e) {
				notFound = e.getMessage();
			}
			try {
				AutomationControlSettingService.removeFlow('Flow:Shipped_Default');
			} catch (AutomationControl.AutomationControlException e) {
				notOwn = e.getMessage();
			}
			String listedName;
			Boolean removedAgain = false;
			if (!anyFlow.isEmpty()) {
				String apiName = (String) anyFlow[0].get('ApiName');
				listedName = AutomationControlSettingService.FLOW_PREFIX + apiName;
				AutomationControlSettingService.addFlow(apiName);
				AutomationControlSettingService.addFlow(apiName);
				List<Automation_Setting__c> listed = AutomationSettingSelector.selectByNames(
					new Set<String>{ listedName }
				);
				Assert.areEqual(1, listed.size(), 'Listed once, however often it is added');
				Assert.isTrue(AutomationControlSettingService.isOwnFlow(listed[0]), 'Own flow');
				Assert.isTrue(listed[0].Enabled__c, 'Its switch starts on');
				Assert.isTrue(
					listed[0].Description__c.contains(listedName),
					'The description names the Automation Name to use'
				);
				AutomationControlSettingService.removeFlow(listedName);
				removedAgain = AutomationSettingSelector.selectByNames(
						new Set<String>{ listedName }
					)
					.isEmpty();
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Core', 'Core_AutomationControl_FlowNotFound'),
				notFound,
				'A flow the org does not have is refused'
			);
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_AutomationControl_NotOwnFlow'),
				notOwn,
				'A package row cannot be removed'
			);
			if (listedName != null) {
				Assert.isTrue(removedAgain, 'Removed from the list');
			}
		}
	}

	@IsTest
	static void catchUpNowIsRefusedWhileOneIsRunning() {
		System.runAs(TestUsers.admin()) {
			AutomationControlSettingService.catchUpRunningForTest = true;
			String message;

			Test.startTest();
			try {
				AutomationControlSettingService.catchUpNow();
			} catch (AutomationControl.AutomationControlException e) {
				message = e.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Core', 'Core_AutomationControl_CatchUpRunning'),
				message,
				'The admin is told a catch-up is already running'
			);
			Assert.areEqual(0, changesNamed('Automation: Catch Up Now'), 'Nothing was started');
		}
	}

	@IsTest
	static void catchUpNowChecksForRunningJobsAndStartsWhenNoneRuns() {
		System.runAs(TestUsers.admin()) {
			Assert.isFalse(
				AutomationControlSettingService.catchUpRunning(),
				'No catch-up job is queued in a fresh test'
			);
			Test.startTest();
			AutomationControlSettingService.catchUpNow();
			Test.stopTest();
			Assert.areEqual(1, changesNamed('Automation: Catch Up Now'), 'Started and recorded');
		}
	}

	@IsTest
	static void catchUpNowStartsTheCatchUpAndIsRecorded() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			AutomationControlController.AutomationPageView page = AutomationControlController.catchUpNow();
			Test.stopTest();

			Assert.isNotNull(page, 'The page comes back');
			Assert.areEqual(1, changesNamed('Automation: Catch Up Now'), 'Recorded');
		}
	}

	@IsTest
	static void thePageCarriesTheRowsTheLabelsAndThePickers() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			AutomationControlController.AutomationPageView page = AutomationControlController.saveControl(
				UserInfo.getOrganizationId(),
				false,
				false
			);
			page = AutomationControlController.addControl(UserInfo.getProfileId());
			page = AutomationControlController.removeControl(UserInfo.getProfileId());
			Test.stopTest();

			Assert.areEqual(1, page.controlRows.size(), 'The organization row');
			Assert.isFalse(page.pausedForEveryone, 'Not paused for everyone');
			Assert.areEqual(
				Schema.SObjectType.BarnCRM_Automation_Control__c.fields.Pause_All__c.getLabel(),
				page.pauseAllLabel,
				'The field label from describe'
			);
			Assert.isFalse(page.profileOptions.isEmpty(), 'Profiles to pick from');
			Assert.isNotNull(page.flowOptions, 'Flows to pick from, possibly none');
			for (AutomationControlController.AutomationView view : page.automations) {
				Assert.isFalse(view.removable, view.automationName + ' ships with BarnCRM');
			}
		}
	}
}
