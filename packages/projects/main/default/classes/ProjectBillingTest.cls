/**
 * Maria bills her client projects (PM-10, R-PM16, R-PM17): New Invoice gathers approved billable
 * time by person and rate, Done milestones, retainer months and billable expenses, marks the work
 * so it is never billed twice, and Send, Mark Paid, Void, Print and Export Invoices do what the
 * admin guide says. With Create invoices off, or without Manage Projects, nothing happens.
 */
@IsTest(
	testFor='ApexClass:ProjectBilling, ApexClass:ProjectBillingController, ApexClass:ProjectInvoiceDocument'
)
private class ProjectBillingTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	/** Turns Create invoices on or off for the org. */
	public static void billing(Boolean turnedOn) {
		OrgSettingsSystemWriter.save(
			Projects_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Projects_Settings__c.Billing_Enabled__c => turnedOn
			}
		);
		SettingsService.clearCaches();
	}

	private static Project__c project(String billingType) {
		Project__c project = ProjectsTestData.project('Active', 100);
		project.Billing_Type__c = billingType;
		project.Retainer_Amount__c = 500;
		update project;
		return project;
	}

	private static Time_Entry__c entry(Id projectId, Decimal hours, Decimal rate, Date day) {
		return new Time_Entry__c(
			Project__c = projectId,
			User__c = UserInfo.getUserId(),
			Date__c = day,
			Hours__c = hours,
			Billable__c = true,
			Bill_Rate__c = rate
		);
	}

	@IsTest
	static void timeAndMaterialsGroupsByPersonAndRateAndBillsOnce() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Project__c project = project(null);
			Date today = Date.today();
			List<Time_Entry__c> entries = new List<Time_Entry__c>();
			for (Integer i = 0; i < 100; i++) {
				entries.add(entry(project.Id, 1, null, today));
			}
			entries.add(entry(project.Id, 2, 150, today));
			Time_Entry__c notBillable = entry(project.Id, 4, null, today);
			notBillable.Billable__c = false;
			entries.add(notBillable);
			entries.add(entry(project.Id, 5, null, today.addDays(-60)));
			insert entries;
			Project_Expense__c expense = new Project_Expense__c(
				Project__c = project.Id,
				Date__c = today,
				Amount__c = 50,
				Category__c = 'Travel',
				Billable__c = true
			);
			insert expense;

			Test.startTest();
			Id invoiceId = ProjectBillingController.buildInvoice(
				project.Id,
				today.addDays(-7),
				today
			);
			Test.stopTest();

			Project_Invoice__c invoice = [
				SELECT
					Status__c,
					Total__c,
					Account__c,
					(SELECT Line_Type__c, Quantity__c FROM Lines__r)
				FROM Project_Invoice__c
				WHERE Id = :invoiceId
			];
			Assert.areEqual('Draft', invoice.Status__c, 'Built as a Draft');
			Assert.areEqual(
				3,
				invoice.Lines__r.size(),
				'Two Time lines (one per rate) and the expense'
			);
			Assert.areEqual(
				100 * 100 + 2 * 150 + 50,
				invoice.Total__c,
				'Hourly Rate when no Bill Rate'
			);
			Assert.areEqual(
				101,
				[SELECT COUNT() FROM Time_Entry__c WHERE Invoice_Line__r.Invoice__c = :invoiceId],
				'Only billable time in the period is marked'
			);
			Assert.isNotNull(
				[SELECT Invoice_Line__c FROM Project_Expense__c WHERE Id = :expense.Id]
				.Invoice_Line__c,
				'The expense is marked'
			);
			try {
				ProjectBilling.build(project.Id, today.addDays(-7), today);
				Assert.fail('Nothing is billed twice');
			} catch (Projects.ProjectsException expected) {
				Assert.isTrue(expected.getMessage().startsWith('Nothing to invoice'), 'Says why');
			}
		}
	}

	@IsTest
	static void sendMarkPaidAndVoidFollowTheStatusRules() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Project__c project = project('Time and Materials');
			insert entry(project.Id, 3, 100, Date.today());
			Id invoiceId = ProjectBilling.build(project.Id, Date.today(), Date.today());

			Test.startTest();
			ProjectBillingController.sendInvoice(invoiceId);
			Project_Invoice__c sent = [
				SELECT Status__c, Invoice_Date__c, Due_Date__c
				FROM Project_Invoice__c
				WHERE Id = :invoiceId
			];
			ProjectBillingController.markPaid(invoiceId, Date.today().addDays(-1));
			Map<String, Object> actions = ProjectBillingController.getInvoiceActions(invoiceId);
			ProjectBillingController.voidInvoice(invoiceId);
			Test.stopTest();

			Assert.areEqual('Sent', sent.Status__c, 'Sent');
			Assert.areEqual(Date.today(), sent.Invoice_Date__c, 'Invoice Date today');
			Assert.areEqual(Date.today().addDays(30), sent.Due_Date__c, 'Due after 30 days');
			Assert.areEqual('Paid', actions.get('status'), 'Marked paid');
			Assert.isTrue((Boolean) actions.get('canManage'), 'Admin acts');
			Project_Invoice__c voided = [
				SELECT Status__c, Paid_Date__c, Amount_Paid__c, (SELECT Id FROM Lines__r)
				FROM Project_Invoice__c
				WHERE Id = :invoiceId
			];
			Assert.areEqual(300, voided.Amount_Paid__c, 'Mark Paid records the full total paid');
			Assert.areEqual('Void', voided.Status__c, 'Void from Paid');
			Assert.areEqual(Date.today().addDays(-1), voided.Paid_Date__c, 'Paid Date as entered');
			Assert.areEqual(1, voided.Lines__r.size(), 'A void invoice keeps its lines');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Time_Entry__c WHERE Invoice_Line__c != NULL],
				'Void frees the time to bill again'
			);
			try {
				ProjectBillingController.sendInvoice(invoiceId);
				Assert.fail('Void is final');
			} catch (AuraHandledException expected) {
				Assert.isTrue(expected.getMessage().contains('Void'), 'Says it is void');
			}
		}
	}

	@IsTest
	static void onlyADraftInvoiceCanBeDeleted() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Project__c project = project('Time and Materials');
			insert entry(project.Id, 3, 100, Date.today());
			Id invoiceId = ProjectBilling.build(project.Id, Date.today(), Date.today());
			ProjectBilling.send(invoiceId);

			Database.DeleteResult sent = Database.delete(invoiceId, false);
			Assert.isFalse(sent.isSuccess(), 'A Sent invoice stays');
			Assert.isTrue(
				sent.getErrors()[0].getMessage().contains('Only a Draft'),
				'Says why and what to do'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Time_Entry__c WHERE Invoice_Line__c != NULL],
				'The billed work stays billed'
			);

			ProjectBilling.voidInvoice(invoiceId);
			Assert.isFalse(Database.delete(invoiceId, false).isSuccess(), 'A Void invoice stays');

			insert entry(project.Id, 1, 100, Date.today());
			Id draftId = ProjectBilling.build(project.Id, Date.today(), Date.today());
			Assert.isTrue(Database.delete(draftId, false).isSuccess(), 'A Draft can be deleted');
		}
	}

	@IsTest
	static void aPeriodTooBigForOneSaveIsRefusedBeforeAnythingIsWritten() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Project__c project = project('Time and Materials');
			insert new List<Time_Entry__c>{
				entry(project.Id, 1, 100, Date.today()),
				entry(project.Id, 2, 100, Date.today())
			};
			ProjectBilling.dmlRowCap = 3;

			try {
				ProjectBilling.build(project.Id, Date.today(), Date.today());
				Assert.fail('Four rows pass a cap of three');
			} catch (Projects.ProjectsException expected) {
				Assert.isTrue(expected.getMessage().contains('shorter period'), 'Asks for less');
			}
			Assert.areEqual(0, [SELECT COUNT() FROM Project_Invoice__c], 'No invoice was made');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Time_Entry__c WHERE Invoice_Line__c != NULL],
				'No time was marked'
			);
		}
	}

	@IsTest
	static void fixedFeeBillsDoneMilestonesAndRetainerEachMonthOnce() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Project__c fixed = project('Fixed Fee');
			Project_Task__c golive = ProjectsTestData.task(fixed.Id, 'Go-Live', Date.today(), true);
			Project_Task__c later = ProjectsTestData.task(fixed.Id, 'Phase 2', Date.today(), true);
			// Fresh rows with only the changed fields: the inserted ones carry the master-detail
			// Project, which a user-mode update refuses to write.
			update new List<Project_Task__c>{
				new Project_Task__c(
					Id = golive.Id,
					Status__c = 'Done',
					Completed_Date__c = Date.today(),
					Billing_Amount__c = 1000
				),
				new Project_Task__c(Id = later.Id, Billing_Amount__c = 2000)
			};
			Project__c retainer = project('Retainer');
			Date start = Date.today().toStartOfMonth().addMonths(-1);

			Test.startTest();
			Id fixedInvoice = ProjectBilling.build(fixed.Id, start, Date.today());
			Id retainerInvoice = ProjectBilling.build(retainer.Id, start, Date.today());
			Test.stopTest();

			Assert.areEqual(
				1000,
				[SELECT Total__c FROM Project_Invoice__c WHERE Id = :fixedInvoice].Total__c,
				'Only the Done milestone'
			);
			Assert.areEqual(
				1000,
				[SELECT Total__c FROM Project_Invoice__c WHERE Id = :retainerInvoice].Total__c,
				'Two months at 500'
			);
			try {
				ProjectBilling.build(retainer.Id, start, Date.today());
				Assert.fail('A month is billed once');
			} catch (Projects.ProjectsException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused in words');
			}
		}
	}

	@IsTest
	static void nothingHappensWhenOffForStaffOrForNotBilled() {
		User staff = ProjectsTestData.staff('Biller');
		Project__c project;
		System.runAs(ProjectsTestData.admin()) {
			project = project('Not Billed');
			Assert.isFalse(
				(Boolean) ProjectBillingController.getProjectBilling(project.Id).get('enabled'),
				'Off at install: nothing shows'
			);
			try {
				ProjectBilling.build(project.Id, Date.today(), Date.today());
				Assert.fail('Off');
			} catch (Projects.ProjectsException expected) {
				Assert.isTrue(expected.getMessage().contains('Create invoices'), 'Says how');
			}
			billing(true);
			try {
				ProjectBilling.build(project.Id, Date.today(), Date.today());
				Assert.fail('Not Billed');
			} catch (Projects.ProjectsException expected) {
				Assert.isTrue(expected.getMessage().contains('Not Billed'), 'Says why');
			}
		}
		System.runAs(staff) {
			Test.startTest();
			try {
				ProjectBillingController.buildInvoice(project.Id, Date.today(), Date.today());
				Assert.fail('Staff cannot invoice');
			} catch (AuraHandledException expected) {
				Assert.isTrue(expected.getMessage().contains('Manage Projects'), 'Says why');
			}
			Test.stopTest();
		}
	}

	@IsTest
	static void printSavesAPdfAndExportStampsOnce() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Project__c project = project(null);
			insert entry(project.Id, 2, 100, Date.today());
			Id invoiceId = ProjectBilling.build(project.Id, Date.today(), Date.today());
			update new Project_Invoice__c(Id = invoiceId, Notes__c = 'Net 30 <thanks>');
			ProjectBilling.send(invoiceId);

			Test.startTest();
			Id documentId = ProjectBillingController.printInvoice(invoiceId);
			List<ProjectViews.Invoice> first = ProjectBillingController.exportInvoices(
				Date.today(),
				Date.today(),
				false
			);
			List<ProjectViews.Invoice> again = ProjectBillingController.exportInvoices(
				Date.today(),
				Date.today(),
				false
			);
			List<ProjectViews.Invoice> included = ProjectBillingController.exportInvoices(
				Date.today(),
				Date.today(),
				true
			);
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM ContentDocumentLink
					WHERE LinkedEntityId = :invoiceId AND ContentDocumentId = :documentId
				],
				'The PDF is in the invoice Files'
			);
			Project_Invoice__c invoice = [
				SELECT
					Name,
					Status__c,
					Invoice_Date__c,
					Due_Date__c,
					Period_Start__c,
					Period_End__c,
					Total__c,
					Amount_Paid__c,
					Notes__c,
					Account__r.Name,
					Contact__r.Name,
					Project__r.Name,
					(
						SELECT
							Description__c,
							Service_Date__c,
							Quantity__c,
							Unit_Price__c,
							Amount__c
						FROM Lines__r
					)
				FROM Project_Invoice__c
				WHERE Id = :invoiceId
			];
			String html = ProjectInvoiceDocument.html(invoice);
			Assert.isTrue(html.contains('Net 30 &lt;thanks&gt;'), 'Values are escaped');
			Assert.isTrue(html.contains('200.00'), 'The total');
			Assert.areEqual(1, first.size(), 'The sent invoice');
			Assert.areEqual(1, first[0].lines.size(), 'With its lines');
			Assert.areEqual(0, again.size(), 'Exported once');
			Assert.areEqual(1, included.size(), 'Unless asked');
		}
	}

	private static Id missingInvoiceId() {
		return Id.valueOf(
			Project_Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
		);
	}

	@IsTest
	static void exportRefusesWhenOffOrWhenTheRangeIsWrong() {
		System.runAs(ProjectsTestData.admin()) {
			String off;
			try {
				ProjectBillingController.exportInvoices(Date.today(), Date.today(), false);
			} catch (AuraHandledException e) {
				off = e.getMessage();
			}
			Assert.isTrue(off.contains('Create invoices'), 'Off says how to turn it on: ' + off);

			billing(true);
			Map<String, List<Date>> ranges = new Map<String, List<Date>>{
				'missing from' => new List<Date>{ null, Date.today() },
				'missing to' => new List<Date>{ Date.today(), null },
				'reversed' => new List<Date>{ Date.today(), Date.today().addDays(-1) }
			};
			for (String label : ranges.keySet()) {
				String refused;
				try {
					ProjectBillingController.exportInvoices(
						ranges.get(label)[0],
						ranges.get(label)[1],
						null
					);
				} catch (AuraHandledException e) {
					refused = e.getMessage();
				}
				Assert.areEqual(
					BarnHelp.text('Projects', 'Projects_Range_Invalid'),
					refused,
					'A ' + label + ' range is refused in words'
				);
			}
			Assert.areEqual(
				0,
				ProjectBillingController.exportInvoices(Date.today(), Date.today(), null).size(),
				'A valid range with nothing billed exports nothing'
			);
		}
	}

	@IsTest
	static void theBillingPartsShowTheProjectsTypeAndHomeShowsOnlyTheSwitches() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Project__c project = project(null);

			Map<String, Object> onProject = ProjectBillingController.getProjectBilling(project.Id);
			Map<String, Object> onHome = ProjectBillingController.getProjectBilling(null);

			Assert.areEqual(true, onProject.get('enabled'), 'Invoices are on');
			Assert.areEqual(true, onProject.get('canManage'), 'The admin manages projects');
			Assert.areEqual(
				ProjectBilling.billingType(
					[SELECT Billing_Type__c FROM Project__c WHERE Id = :project.Id]
				),
				onProject.get('billingType'),
				'The type the project bills by'
			);
			Assert.areEqual(true, onHome.get('enabled'), 'Projects Home: on');
			Assert.isNull(onHome.get('billingType'), 'Projects Home has no project type');
		}
	}

	@IsTest
	static void theInvoicePageShowsItsActionsForADraft() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Project__c project = project(null);
			insert entry(project.Id, 2, 100, Date.today());
			Id invoiceId = ProjectBilling.build(project.Id, Date.today(), Date.today());

			Map<String, Object> actions = ProjectBillingController.getInvoiceActions(invoiceId);

			Assert.areEqual(true, actions.get('enabled'), 'Invoices are on');
			Assert.areEqual(true, actions.get('canManage'), 'The admin may act');
			Assert.areEqual(
				ProjectBilling.DRAFT,
				actions.get('status'),
				'A new invoice is a draft'
			);
			Assert.areEqual(200, (Decimal) actions.get('balance'), 'Nothing paid yet');
		}
	}

	@IsTest
	static void anInvoiceThatCannotBeFoundIsSaidInOneMessageForEveryAction() {
		System.runAs(ProjectsTestData.admin()) {
			billing(true);
			Id missing = missingInvoiceId();
			Map<String, Boolean> failed = new Map<String, Boolean>();
			Test.startTest();
			try {
				ProjectBillingController.getInvoiceActions(missing);
			} catch (AuraHandledException e) {
				failed.put(
					'actions',
					e.getMessage() == BarnHelp.text('Projects', 'Projects_Error_Generic')
				);
			}
			try {
				ProjectBillingController.sendInvoice(missing);
			} catch (AuraHandledException e) {
				failed.put('send', true);
			}
			try {
				ProjectBillingController.markPaid(missing, Date.today());
			} catch (AuraHandledException e) {
				failed.put('paid', true);
			}
			try {
				ProjectBillingController.voidInvoice(missing);
			} catch (AuraHandledException e) {
				failed.put('void', true);
			}
			try {
				ProjectBillingController.printInvoice(missing);
			} catch (AuraHandledException e) {
				failed.put('print', true);
			}
			try {
				ProjectBillingController.sendPaymentLink(missing);
			} catch (AuraHandledException e) {
				failed.put('link', true);
			}
			Test.stopTest();

			Assert.areEqual(6, failed.size(), 'Every action answers with a message, not a stack');
			Assert.isTrue(failed.get('actions'), 'An unexpected error shows the generic message');
		}
	}

	@IsTest
	static void recognizeRevenueAnswersInWordsWhenRevenueIsOff() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = project(null);
			String refused;
			try {
				ProjectBillingController.recognizeRevenue(project.Id, Date.today().addMonths(-1));
			} catch (AuraHandledException e) {
				refused = e.getMessage();
			}
			Assert.areEqual(
				BarnHelp.text('Projects', 'Projects_Revenue_Off'),
				refused,
				'Recognize Revenue says it is off'
			);
		}
	}
}
