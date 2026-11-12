/**
 * Project invoices (PM-10; ADR-NEXT `NEXT-projects-psa.md` decision 6; canonical model R-PM16
 * and R-PM17): New Invoice builds a Draft from the project's unbilled work, then Send, Mark Paid
 * and Void. Every step needs Manage Projects and Create invoices on, and runs in user mode.
 * BarnCRM takes no payment here: Paid is a status the admin sets, or Payments reports (R-PM22).
 */
public with sharing class ProjectBilling {
	public static final String DRAFT = 'Draft';
	public static final String SENT = 'Sent';
	public static final String PAID = 'Paid';
	public static final String VOIDED = 'Void';
	public static final String TIME_AND_MATERIALS = 'Time and Materials';
	public static final String FIXED_FEE = 'Fixed Fee';
	public static final String RETAINER = 'Retainer';
	public static final String NOT_BILLED = 'Not Billed';
	/** R-PM10: time and expenses count when their Status is blank or Approved. */
	public static final String COUNTED = '(Status__c = NULL OR Status__c = \'Approved\')';

	/** Most DML rows one build may write (invoice, lines, marked sources); the limit is 10,000. */
	@TestVisible
	private static Integer dmlRowCap = 9000;

	/** R-PM16: the Draft for a period, its lines, and each source marked with its line. */
	public static Id build(Id projectId, Date periodStart, Date periodEnd) {
		requireBilling();
		if (periodStart == null || periodEnd == null || periodEnd < periodStart) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_PeriodInvalid'));
		}
		Project__c project = [
			SELECT Id, Billing_Type__c, Hourly_Rate__c, Retainer_Amount__c, Account__c, Contact__c
			FROM Project__c
			WHERE Id = :projectId
			WITH USER_MODE
		];
		String type = billingType(project);
		if (type == NOT_BILLED) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_NotBilled'));
		}
		List<Project_Invoice_Line__c> lines = new List<Project_Invoice_Line__c>();
		List<List<SObject>> sources = new List<List<SObject>>();
		if (type == TIME_AND_MATERIALS) {
			addTime(project, periodStart, periodEnd, lines, sources);
		} else if (type == FIXED_FEE) {
			for (Project_Task__c milestone : [
				SELECT Id, Name, Billing_Amount__c, Completed_Date__c
				FROM Project_Task__c
				WHERE
					Project__c = :projectId
					AND Milestone__c = TRUE
					AND Status__c = :Projects.DONE
					AND Billing_Amount__c != NULL
					AND Completed_Date__c <= :periodEnd
					AND Invoice_Line__c = NULL
				WITH USER_MODE
				ORDER BY Completed_Date__c
				LIMIT 500
			]) {
				add(lines, sources, 'Milestone', milestone.Name, milestone.Completed_Date__c, 1);
				lines[lines.size() - 1].Unit_Price__c = milestone.Billing_Amount__c;
				sources[sources.size() - 1].add(milestone);
			}
		} else {
			addRetainer(project, periodStart, periodEnd, lines, sources);
		}
		for (
			Project_Expense__c expense : (List<Project_Expense__c>) Database.queryWithBinds(
				'SELECT Id, Category__c, Description__c, Date__c, Amount__c FROM Project_Expense__c ' +
					'WHERE Project__c = :projectId AND Billable__c = TRUE AND Invoice_Line__c = NULL ' +
					'AND Date__c >= :periodStart AND Date__c <= :periodEnd AND ' +
					COUNTED +
					' ORDER BY Date__c LIMIT 2000',
				new Map<String, Object>{
					'projectId' => projectId,
					'periodStart' => periodStart,
					'periodEnd' => periodEnd
				},
				AccessLevel.USER_MODE
			)
		) {
			String what =
				expense.Category__c +
				(String.isBlank(expense.Description__c) ? '' : ': ' + expense.Description__c);
			add(lines, sources, 'Expense', what, expense.Date__c, 1);
			lines[lines.size() - 1].Unit_Price__c = expense.Amount__c;
			sources[sources.size() - 1].add(expense);
		}
		if (lines.isEmpty()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_Nothing'));
		}
		// Every source is updated and every line inserted: refuse a period too big before any DML.
		Integer rows = 1 + lines.size();
		for (List<SObject> members : sources) {
			rows += members.size();
		}
		if (rows > dmlRowCap) {
			throw Projects.refuse(
				BarnHelp.text('Projects', 'Projects_Invoice_TooMany', new List<Object>{ rows })
			);
		}
		Project_Invoice__c invoice = new Project_Invoice__c(
			Project__c = projectId,
			Status__c = DRAFT,
			Account__c = project.Account__c,
			Contact__c = project.Contact__c,
			Period_Start__c = periodStart,
			Period_End__c = periodEnd
		);
		insert as user invoice;
		for (Project_Invoice_Line__c line : lines) {
			line.Invoice__c = invoice.Id;
		}
		insert as user lines;
		List<SObject> marked = new List<SObject>();
		for (Integer i = 0; i < lines.size(); i++) {
			for (SObject source : sources[i]) {
				SObject change = source.getSObjectType().newSObject(source.Id);
				change.put('Invoice_Line__c', lines[i].Id);
				marked.add(change);
			}
		}
		// Lines were added time, then milestones, then expenses, so each object's rows are together.
		update as user marked;
		return invoice.Id;
	}

	/** R-PM17 Send: Draft to Sent; Invoice Date today and Due Date after it, each when blank. */
	public static void send(Id invoiceId) {
		Project_Invoice__c invoice = load(invoiceId, DRAFT);
		if (invoice.Total__c == null || invoice.Lines__r.isEmpty()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_NoLines'));
		}
		Date sentOn = invoice.Invoice_Date__c == null ? Date.today() : invoice.Invoice_Date__c;
		update as user new Project_Invoice__c(
			Id = invoiceId,
			Status__c = SENT,
			Invoice_Date__c = sentOn,
			Due_Date__c = invoice.Due_Date__c == null
				? sentOn.addDays(ProjectsSettings.invoiceDueDays())
				: invoice.Due_Date__c
		);
	}

	/** R-PM17 Mark Paid: a Sent invoice the client paid directly, on the date given. */
	public static void markPaid(Id invoiceId, Date paidDate) {
		Project_Invoice__c invoice = load(invoiceId, SENT);
		update as user new Project_Invoice__c(
			Id = invoiceId,
			Status__c = PAID,
			Amount_Paid__c = invoice.Total__c,
			Paid_Date__c = paidDate == null ? Date.today() : paidDate
		);
	}

	/** R-PM17 Void: final, keeps the lines, and frees the work on them to be billed again. */
	public static void voidInvoice(Id invoiceId) {
		Project_Invoice__c invoice = load(invoiceId, null);
		if (invoice.Status__c == VOIDED) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_AlreadyVoid'));
		}
		Set<Id> lineIds = new Map<Id, Project_Invoice_Line__c>(invoice.Lines__r).keySet();
		List<SObject> freed = new List<SObject>();
		freed.addAll(
			(List<SObject>) [
				SELECT Id
				FROM Time_Entry__c
				WHERE Invoice_Line__c IN :lineIds
				WITH USER_MODE
				LIMIT 10000
			]
		);
		freed.addAll(
			(List<SObject>) [
				SELECT Id
				FROM Project_Expense__c
				WHERE Invoice_Line__c IN :lineIds
				WITH USER_MODE
				LIMIT 5000
			]
		);
		freed.addAll(
			(List<SObject>) [
				SELECT Id
				FROM Project_Task__c
				WHERE Invoice_Line__c IN :lineIds
				WITH USER_MODE
				LIMIT 1000
			]
		);
		for (SObject record : freed) {
			record.put('Invoice_Line__c', null);
		}
		update as user freed;
		update as user new Project_Invoice__c(Id = invoiceId, Status__c = VOIDED);
	}

	/** Refuses, in words, when invoices are off or the person lacks Manage Projects. */
	public static void requireBilling() {
		if (!ProjectsSettings.billingEnabled()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Billing_Off'));
		}
		Projects.requireManage();
	}

	/** A blank Billing Type reads as Time and Materials (older projects). */
	public static String billingType(Project__c project) {
		return String.isBlank(project.Billing_Type__c)
			? TIME_AND_MATERIALS
			: project.Billing_Type__c;
	}

	/** The invoice with its lines, refused unless it has the status asked for (any when null). */
	private static Project_Invoice__c load(Id invoiceId, String status) {
		requireBilling();
		Project_Invoice__c invoice = [
			SELECT
				Id,
				Status__c,
				Total__c,
				Invoice_Date__c,
				Due_Date__c,
				(SELECT Id FROM Lines__r LIMIT 2000)
			FROM Project_Invoice__c
			WHERE Id = :invoiceId
			WITH USER_MODE
		];
		if (status != null && invoice.Status__c != status) {
			throw Projects.refuse(
				BarnHelp.text(
					'Projects',
					'Projects_Invoice_WrongStatus',
					new List<Object>{ invoice.Status__c, status }
				)
			);
		}
		return invoice;
	}

	/** Time and Materials: one Time line per person and Bill Rate (no rate: the Hourly Rate). */
	private static void addTime(
		Project__c project,
		Date periodStart,
		Date periodEnd,
		List<Project_Invoice_Line__c> lines,
		List<List<SObject>> sources
	) {
		Map<String, Integer> lineFor = new Map<String, Integer>();
		for (
			Time_Entry__c entry : (List<Time_Entry__c>) Database.queryWithBinds(
				'SELECT Id, User__c, User__r.Name, Hours__c, Bill_Rate__c FROM Time_Entry__c ' +
					'WHERE Project__c = :projectId AND Billable__c = TRUE AND Invoice_Line__c = NULL ' +
					'AND Date__c >= :periodStart AND Date__c <= :periodEnd AND ' +
					COUNTED +
					' ORDER BY User__r.Name, Date__c LIMIT 10000',
				new Map<String, Object>{
					'projectId' => project.Id,
					'periodStart' => periodStart,
					'periodEnd' => periodEnd
				},
				AccessLevel.USER_MODE
			)
		) {
			Decimal rate = entry.Bill_Rate__c == null ? project.Hourly_Rate__c : entry.Bill_Rate__c;
			rate = rate == null ? 0 : rate;
			String key = entry.User__c + '|' + rate;
			if (!lineFor.containsKey(key)) {
				lineFor.put(key, lines.size());
				add(
					lines,
					sources,
					'Time',
					BarnHelp.text(
						'Projects',
						'Projects_Invoice_TimeLine',
						new List<Object>{ entry.User__r?.Name, rate.format() }
					),
					periodEnd,
					0
				);
				lines[lines.size() - 1].Unit_Price__c = rate;
			}
			Integer at = lineFor.get(key);
			lines[at].Quantity__c += entry.Hours__c;
			sources[at].add(entry);
		}
	}

	/** Retainer: one line per month of the period not already on an invoice that is not Void. */
	private static void addRetainer(
		Project__c project,
		Date periodStart,
		Date periodEnd,
		List<Project_Invoice_Line__c> lines,
		List<List<SObject>> sources
	) {
		if (project.Retainer_Amount__c == null) {
			return;
		}
		Set<Date> billed = new Set<Date>();
		for (Project_Invoice_Line__c line : [
			SELECT Service_Date__c
			FROM Project_Invoice_Line__c
			WHERE
				Invoice__r.Project__c = :project.Id
				AND Invoice__r.Status__c != :VOIDED
				AND Line_Type__c = :RETAINER
			WITH USER_MODE
			LIMIT 2000
		]) {
			if (line.Service_Date__c != null) {
				billed.add(line.Service_Date__c.toStartOfMonth());
			}
		}
		for (
			Date month = periodStart.toStartOfMonth();
			month <= periodEnd;
			month = month.addMonths(1)
		) {
			if (!billed.contains(month)) {
				String name = Datetime.newInstance(month, Time.newInstance(12, 0, 0, 0))
					.format('MMMM yyyy');
				add(
					lines,
					sources,
					RETAINER,
					BarnHelp.text(
						'Projects',
						'Projects_Invoice_RetainerLine',
						new List<Object>{ name }
					),
					month,
					1
				);
				lines[lines.size() - 1].Unit_Price__c = project.Retainer_Amount__c;
			}
		}
	}

	private static void add(
		List<Project_Invoice_Line__c> lines,
		List<List<SObject>> sources,
		String type,
		String description,
		Date serviceDate,
		Decimal quantity
	) {
		lines.add(
			new Project_Invoice_Line__c(
				Line_Type__c = type,
				Description__c = description.abbreviate(255),
				Service_Date__c = serviceDate,
				Quantity__c = quantity
			)
		);
		sources.add(new List<SObject>());
	}
}
