/**
 * What the Projects pages read, as plain shapes with unprefixed names (dynamic-apex.md
 * section 4). A record handed to Lightning keys its fields by API name, which gains the
 * namespace prefix once the package has one, so no Projects controller returns a record. Each
 * shape reads only the fields its controllers' queries select.
 */
public with sharing class ProjectViews {
	/** A record named for a picker: a project to log time to, a task for a new row. */
	public class Named {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;

		public Named(SObject record) {
			id = record.Id;
			name = (String) record.get('Name');
		}
	}

	public class Project {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String health;
		@AuraEnabled
		public String healthReasons;
		@AuraEnabled
		public Date startDate;
		@AuraEnabled
		public Date targetDate;
		@AuraEnabled
		public Boolean isTemplate;
		@AuraEnabled
		public Decimal taskCount;
		@AuraEnabled
		public Decimal tasksDone;
		@AuraEnabled
		public Decimal estimatedHours;
		@AuraEnabled
		public Decimal actualHours;
		@AuraEnabled
		public Decimal budgetHours;
		@AuraEnabled
		public Decimal changeHours;
		@AuraEnabled
		public Decimal budgetAmount;
		@AuraEnabled
		public Decimal actualCost;
		@AuraEnabled
		public Decimal remainingBudget;
		@AuraEnabled
		public String ownerName;

		public Project(Project__c record) {
			id = record.Id;
			name = record.Name;
			status = record.Status__c;
			health = record.Health__c;
			healthReasons = record.Health_Reasons__c;
			startDate = record.Start_Date__c;
			targetDate = record.Target_Date__c;
			isTemplate = record.Is_Template__c;
			taskCount = record.Tasks__c;
			tasksDone = record.Tasks_Done__c;
			estimatedHours = record.Estimated_Hours__c;
			actualHours = record.Actual_Hours__c;
			budgetHours = record.Budget_Hours__c;
			changeHours = record.Change_Hours__c;
			budgetAmount = record.Budget_Amount__c;
			actualCost = record.Actual_Cost__c;
			remainingBudget = record.Remaining_Budget__c;
			ownerName = record.Owner?.Name;
		}
	}

	public class Phase {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Decimal sortOrder;
		@AuraEnabled
		public Date startDate;
		@AuraEnabled
		public Date endDate;

		public Phase(Project_Phase__c record) {
			id = record.Id;
			name = record.Name;
			sortOrder = record.Sort_Order__c;
			startDate = record.Start_Date__c;
			endDate = record.End_Date__c;
		}
	}

	public class Task {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Id projectId;
		@AuraEnabled
		public String projectName;
		@AuraEnabled
		public Id phaseId;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Boolean milestone;
		@AuraEnabled
		public Date startDate;
		@AuraEnabled
		public Date dueDate;
		@AuraEnabled
		public Date completedDate;
		@AuraEnabled
		public Decimal estimatedHours;
		@AuraEnabled
		public Decimal sortOrder;
		@AuraEnabled
		public String assignedToName;

		public Task(Project_Task__c record) {
			id = record.Id;
			name = record.Name;
			projectId = record.Project__c;
			projectName = record.Project__r?.Name;
			phaseId = record.Phase__c;
			status = record.Status__c;
			milestone = record.Milestone__c;
			startDate = record.Start_Date__c;
			dueDate = record.Due_Date__c;
			completedDate = record.Completed_Date__c;
			estimatedHours = record.Estimated_Hours__c;
			sortOrder = record.Sort_Order__c;
			assignedToName = record.Assigned_To__r?.Name;
		}
	}

	/** A time entry or an expense on the person's week; the other kind's values stay null. */
	public class WeekRow {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public Id projectId;
		@AuraEnabled
		public String projectName;
		@AuraEnabled
		public Id taskId;
		@AuraEnabled
		public String taskName;
		@AuraEnabled
		public Date entryDate;
		@AuraEnabled
		public Decimal hours;
		@AuraEnabled
		public String category;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public Boolean billable;
		@AuraEnabled
		public String notes;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String rejectionReason;

		public WeekRow(Time_Entry__c record) {
			id = record.Id;
			projectId = record.Project__c;
			projectName = record.Project__r?.Name;
			taskId = record.Task__c;
			taskName = record.Task__r?.Name;
			entryDate = record.Date__c;
			hours = record.Hours__c;
			billable = record.Billable__c;
			notes = record.Notes__c;
			status = record.Status__c;
			rejectionReason = record.Rejection_Reason__c;
		}

		public WeekRow(Project_Expense__c record) {
			id = record.Id;
			projectId = record.Project__c;
			projectName = record.Project__r?.Name;
			entryDate = record.Date__c;
			category = record.Category__c;
			amount = record.Amount__c;
			billable = record.Billable__c;
			notes = record.Description__c;
			status = record.Status__c;
			rejectionReason = record.Rejection_Reason__c;
		}
	}

	/** An invoice for Export Invoices, with its lines, named as the CSV columns are. */
	public class Invoice {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String project;
		@AuraEnabled
		public String client;
		@AuraEnabled
		public Date invoiceDate;
		@AuraEnabled
		public Date dueDate;
		@AuraEnabled
		public Date paidDate;
		@AuraEnabled
		public Decimal total;
		@AuraEnabled
		public Decimal amountPaid;
		@AuraEnabled
		public List<InvoiceLine> lines = new List<InvoiceLine>();

		public Invoice(Project_Invoice__c record) {
			name = record.Name;
			status = record.Status__c;
			project = record.Project__r?.Name;
			client = record.Account__r?.Name;
			invoiceDate = record.Invoice_Date__c;
			dueDate = record.Due_Date__c;
			paidDate = record.Paid_Date__c;
			total = record.Total__c;
			amountPaid = record.Amount_Paid__c;
			for (Project_Invoice_Line__c line : record.Lines__r) {
				lines.add(new InvoiceLine(line));
			}
		}
	}

	public class InvoiceLine {
		@AuraEnabled
		public String lineType;
		@AuraEnabled
		public String description;
		@AuraEnabled
		public Date serviceDate;
		@AuraEnabled
		public Decimal quantity;
		@AuraEnabled
		public Decimal unitPrice;
		@AuraEnabled
		public Decimal amount;

		public InvoiceLine(Project_Invoice_Line__c record) {
			lineType = record.Line_Type__c;
			description = record.Description__c;
			serviceDate = record.Service_Date__c;
			quantity = record.Quantity__c;
			unitPrice = record.Unit_Price__c;
			amount = record.Amount__c;
		}
	}

	public static List<Phase> phases(List<Project_Phase__c> records) {
		List<Phase> views = new List<Phase>();
		for (Project_Phase__c record : records) {
			views.add(new Phase(record));
		}
		return views;
	}

	public static List<Task> tasks(List<Project_Task__c> records) {
		List<Task> views = new List<Task>();
		for (Project_Task__c record : records) {
			views.add(new Task(record));
		}
		return views;
	}

	public static List<Named> named(List<SObject> records) {
		List<Named> views = new List<Named>();
		for (SObject record : records) {
			views.add(new Named(record));
		}
		return views;
	}
}
