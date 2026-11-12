/**
 * R-PM3: a shipped template builds a dated project with its phases, tasks and milestones, a
 * template project is copied with its dates moved, and a bad key is refused in words.
 */
@IsTest(testFor='ApexClass:ProjectTemplates')
private class ProjectTemplatesTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	@IsTest
	static void theShippedImplementationTemplateBuildsADatedProject() {
		System.runAs(ProjectsTestData.admin()) {
			Date start = Date.newInstance(2027, 1, 4);

			Test.startTest();
			List<ProjectTemplates.Template> listed = ProjectTemplates.available();
			Id projectId = ProjectTemplates.create(
				'salesforce_implementation',
				'Our Rollout',
				start,
				null,
				null
			);
			Test.stopTest();

			Assert.areEqual(
				'salesforce_implementation',
				listed[0].key,
				'The shipped templates come first'
			);
			Assert.isTrue(listed[0].shipped, 'Marked as shipped');
			Project__c project = [
				SELECT
					Name,
					Type__c,
					Status__c,
					Target_Date__c,
					Template_Key__c,
					(SELECT Name, Start_Date__c FROM Phases__r ORDER BY Sort_Order__c),
					(
						SELECT Name, Due_Date__c, Milestone__c, Phase__c
						FROM Tasks__r
						WHERE Milestone__c = TRUE
					)
				FROM Project__c
				WHERE Id = :projectId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Our Rollout', project.Name, 'Named as asked');
			Assert.areEqual('Salesforce Implementation', project.Type__c, 'Type from the template');
			Assert.areEqual('Planned', project.Status__c, 'Starts Planned');
			Assert.areEqual(start.addDays(98), project.Target_Date__c, 'Fourteen weeks');
			Assert.areEqual(7, project.Phases__r.size(), 'Seven phases');
			Assert.areEqual('Discovery', project.Phases__r[0].Name, 'In order');
			Assert.areEqual('Go-Live', project.Phases__r[6].Name, 'Go-Live last');
			Assert.areEqual(4, project.Tasks__r.size(), 'Four milestones, Go-Live among them');
			for (Project_Task__c milestone : project.Tasks__r) {
				Assert.isNotNull(milestone.Phase__c, 'Each milestone is in its phase');
			}
		}
	}

	@IsTest
	static void aTemplateProjectIsCopiedWithItsDatesMoved() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c template = new Project__c(
				Name = 'Office Move',
				Type__c = 'Internal',
				Status__c = 'Planned',
				Is_Template__c = true,
				Start_Date__c = Date.newInstance(2026, 1, 1),
				Target_Date__c = Date.newInstance(2026, 1, 31),
				Budget_Hours__c = 40
			);
			insert template;
			Project_Phase__c phase = new Project_Phase__c(
				Project__c = template.Id,
				Name = 'Pack',
				Start_Date__c = Date.newInstance(2026, 1, 1),
				End_Date__c = Date.newInstance(2026, 1, 10)
			);
			insert phase;
			insert new Project_Task__c(
				Project__c = template.Id,
				Phase__c = phase.Id,
				Name = 'Boxes',
				Status__c = 'Done',
				Due_Date__c = Date.newInstance(2026, 1, 5),
				Estimated_Hours__c = 4
			);
			insert new Project_Assignment__c(
				Project__c = template.Id,
				Role__c = 'Mover',
				Resource__c = UserInfo.getUserId(),
				Planned_Hours__c = 20,
				Start_Date__c = Date.newInstance(2026, 1, 1)
			);

			Test.startTest();
			Id copyId = ProjectTemplates.create(
				template.Id,
				null,
				Date.newInstance(2026, 3, 1),
				null,
				null
			);
			Test.stopTest();

			Project__c copy = [
				SELECT
					Name,
					Is_Template__c,
					Target_Date__c,
					Budget_Hours__c,
					(SELECT Name, Status__c, Due_Date__c, Phase__r.Name FROM Tasks__r),
					(SELECT Role__c, Resource__c, Start_Date__c FROM Assignments__r)
				FROM Project__c
				WHERE Id = :copyId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Office Move', copy.Name, 'The template name when none is given');
			Assert.isFalse(copy.Is_Template__c, 'The copy is not a template');
			Assert.areEqual(
				Date.newInstance(2026, 3, 31),
				copy.Target_Date__c,
				'Target moved with the start'
			);
			Assert.areEqual(40, copy.Budget_Hours__c, 'Budget copied');
			Assert.areEqual('Not Started', copy.Tasks__r[0].Status__c, 'Tasks start fresh');
			Assert.areEqual(
				Date.newInstance(2026, 3, 5),
				copy.Tasks__r[0].Due_Date__c,
				'Due date moved'
			);
			Assert.areEqual('Pack', copy.Tasks__r[0].Phase__r.Name, 'In the copied phase');
			Assert.areEqual('Mover', copy.Assignments__r[0].Role__c, 'The role is copied');
			Assert.isNull(copy.Assignments__r[0].Resource__c, 'The person is not');
			Assert.areEqual(
				Date.newInstance(2026, 3, 1),
				copy.Assignments__r[0].Start_Date__c,
				'Assignment date moved'
			);
		}
	}

	@IsTest
	static void anUnknownTemplateIsRefusedInWords() {
		System.runAs(ProjectsTestData.admin()) {
			Test.startTest();
			try {
				ProjectsController.createFromTemplate(
					'no_such_template',
					'X',
					Date.today(),
					null,
					null
				);
				Assert.fail('An unknown template is refused');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Projects', 'Projects_Template_Missing'),
					refused.getMessage(),
					'Said in words'
				);
			}
			Test.stopTest();
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Project__c WITH SYSTEM_MODE],
				'Nothing was made'
			);
		}
	}
}
