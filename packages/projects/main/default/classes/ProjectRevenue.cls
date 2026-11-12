/**
 * Recognized revenue (PM-11; ADR-NEXT `NEXT-projects-psa.md` decision 7; canonical model R-PM19):
 * one Project Revenue row per billed project per closed month, so a closed month never moves.
 * A row is what the project earned through the month's last day, as counted at the run, less
 * every earlier row; time approved late or a falling percent complete lands in the next month.
 *
 * The nightly step (6:42 AM, its own switch, run only while Show financials and recognize revenue
 * is on) writes, in system mode as whoever scheduled the run (ADR-0021), the row for the month
 * just closed of each project that has none yet, 100 projects per queued job, up to 2,000.
 * Recognize Revenue on the project redoes one month in user mode, with Manage Projects.
 */
public with sharing class ProjectRevenue implements Schedulable, Queueable {
	public static final String JOB_NAME = 'BarnCRM Projects Revenue';
	private static final Integer CHUNK = 100;
	private static final Integer MAX_ROWS = 2000;
	private static final String FIELDS = 'Id, Billing_Type__c, Budget_Amount__c, Change_Amount__c, Percent_Complete__c, Retainer_Amount__c, Hourly_Rate__c, Start_Date__c, Completed_Date__c';

	private final Date month;
	private final Id afterId;
	private final Integer done;

	public ProjectRevenue() {
		this(null, null, 0);
	}

	@TestVisible
	private ProjectRevenue(Date month, Id afterId, Integer done) {
		this.month = month;
		this.afterId = afterId;
		this.done = done;
	}

	/** The step as BarnCRM's nightly run lists it, with a switch that ships on. */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				BarnHelp.text('Projects', 'Projects_Revenue_StepName'),
				6,
				42,
				new ProjectRevenue()
			)
			.withSwitch(true)
			.activeWhen(ProjectsSettings.revenueEnabled());
	}

	/** Starts the month just closed. */
	public void execute(SchedulableContext context) {
		if (ProjectsSettings.revenueEnabled()) {
			System.enqueueJob(
				new ProjectRevenue(Date.today().toStartOfMonth().addMonths(-1), null, 0)
			);
		}
	}

	/** One chunk of projects: rows for those with none yet for the month; then the next chunk. */
	public void execute(QueueableContext context) {
		try {
			Date monthEnd = month.addMonths(1).addDays(-1);
			Map<String, Object> binds = new Map<String, Object>{
				'notBilled' => ProjectBilling.NOT_BILLED,
				'running' => new List<String>{ Projects.ACTIVE, 'On Hold' },
				'monthStart' => month,
				'monthEnd' => monthEnd,
				'afterId' => afterId,
				'chunk' => CHUNK + 1
			};
			// Access mode: system, as whoever scheduled the nightly run (ADR-0021).
			List<Project__c> found = Database.queryWithBinds(
				'SELECT ' +
					FIELDS +
					' FROM Project__c WHERE Is_Template__c = FALSE AND Billing_Type__c != :notBilled' +
					' AND (Start_Date__c = NULL OR Start_Date__c <= :monthEnd)' +
					' AND Id NOT IN (SELECT Project__c FROM Project_Revenue__c WHERE Month__c = :monthStart)' +
					' AND (Status__c IN :running OR (Status__c = \'Completed\' AND Completed_Date__c >= :monthStart' +
					' AND Completed_Date__c <= :monthEnd))' +
					(afterId == null ? '' : ' AND Id > :afterId') +
					' ORDER BY Id LIMIT :chunk',
				binds,
				AccessLevel.SYSTEM_MODE
			);
			if (found.isEmpty()) {
				return;
			}
			// The query took one row beyond the chunk to tell whether another chunk exists.
			Boolean more = found.size() > CHUNK;
			List<Project__c> batch = new List<Project__c>();
			for (Integer i = 0; i < Math.min(found.size(), CHUNK); i++) {
				batch.add(found[i]);
			}
			save(recognize(batch, month, AccessLevel.SYSTEM_MODE), AccessLevel.SYSTEM_MODE);
			Integer total = done + batch.size();
			if (more && total >= MAX_ROWS) {
				ErrorLogger.logMessage(
					BarnHelp.text(
						'Projects',
						'Projects_Revenue_CapReached',
						new List<Object>{ MAX_ROWS }
					),
					'ProjectRevenue',
					ErrorLogger.SEVERITY_WARNING
				);
			} else if (more && !Test.isRunningTest()) {
				System.enqueueJob(new ProjectRevenue(month, batch[CHUNK - 1].Id, total));
			}
		} catch (Exception e) {
			ErrorLogger.log(e, 'ProjectRevenue');
		}
	}

	/** Recognize Revenue: writes or redoes one project's row for a closed month, as the person. */
	public static Id recognizeMonth(Id projectId, Date anyDay) {
		if (!ProjectsSettings.revenueEnabled()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Revenue_Off'));
		}
		Projects.requireManage();
		Date month = anyDay == null ? null : anyDay.toStartOfMonth();
		if (month == null || month >= Date.today().toStartOfMonth()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Revenue_OpenMonth'));
		}
		List<Project__c> found = Database.queryWithBinds(
			'SELECT ' + FIELDS + ' FROM Project__c WHERE Id = :projectId',
			new Map<String, Object>{ 'projectId' => projectId },
			AccessLevel.USER_MODE
		);
		List<Project_Revenue__c> rows = recognize(found, month, AccessLevel.USER_MODE);
		if (rows.isEmpty()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_NotBilled'));
		}
		save(rows, AccessLevel.USER_MODE);
		return rows[0].Id;
	}

	/** R-PM19: each billed project's row for the month: earned through its end less earlier rows. */
	@TestVisible
	private static List<Project_Revenue__c> recognize(
		List<Project__c> projects,
		Date month,
		AccessLevel mode
	) {
		List<Project_Revenue__c> rows = new List<Project_Revenue__c>();
		List<Project__c> billed = new List<Project__c>();
		for (Project__c project : projects) {
			if (ProjectBilling.billingType(project) != ProjectBilling.NOT_BILLED) {
				billed.add(project);
			}
		}
		if (billed.isEmpty()) {
			return rows;
		}
		Map<Id, Decimal[]> earned = earned(billed, month.addMonths(1).addDays(-1), true, mode);
		Map<Id, Decimal[]> earlier = new Map<Id, Decimal[]>();
		// Access mode: the caller's, passed as `mode`.
		for (
			AggregateResult sum : (List<AggregateResult>) Database.queryWithBinds(
				'SELECT Project__c p, SUM(Recognized_Amount__c) r, SUM(Cost_Amount__c) c FROM Project_Revenue__c ' +
				'WHERE Project__c IN :billed AND Month__c < :month GROUP BY Project__c',
				new Map<String, Object>{ 'billed' => billed, 'month' => month },
				mode
			)
		) {
			earlier.put(
				(Id) sum.get('p'),
				new List<Decimal>{ num(sum.get('r')), num(sum.get('c')) }
			);
		}
		for (Project__c project : billed) {
			Decimal[] upTo = earned.get(project.Id);
			Decimal[] past = earlier.containsKey(project.Id)
				? earlier.get(project.Id)
				: new List<Decimal>{ 0, 0 };
			String method = ProjectBilling.billingType(project);
			rows.add(
				new Project_Revenue__c(
					Project__c = project.Id,
					Month__c = month,
					Month_Key__c = key(project.Id, month),
					Method__c = method,
					Recognized_Amount__c = upTo[0] - past[0],
					Cost_Amount__c = upTo[1] - past[1],
					Percent_Complete__c = method == ProjectBilling.FIXED_FEE
						? num(project.Percent_Complete__c)
						: null
				)
			);
		}
		return rows;
	}

	/**
	 * What each project earned and cost through a day (R-PM19, R-PM21), from counted time and
	 * expenses (R-PM10): `{ revenue, cost }`. Cost is 0 when `withCost` is false (it needs
	 * Projects Admin). Time with no Bill Rate earns the project's Hourly Rate.
	 */
	public static Map<Id, Decimal[]> earned(
		List<Project__c> projects,
		Date through,
		Boolean withCost,
		AccessLevel mode
	) {
		Map<Id, Decimal[]> out = new Map<Id, Decimal[]>();
		Map<Id, Project__c> byId = new Map<Id, Project__c>(projects);
		for (Project__c project : projects) {
			out.put(project.Id, new List<Decimal>{ 0, 0 });
		}
		Map<String, Object> binds = new Map<String, Object>{
			'ids' => byId.keySet(),
			'through' => through
		};
		String counted =
			' WHERE Project__c IN :ids AND Date__c <= :through AND ' + ProjectBilling.COUNTED;
		// Access mode: the caller's, passed as `mode`.
		for (
			AggregateResult sum : (List<AggregateResult>) Database.queryWithBinds(
				'SELECT Project__c p, Billable__c b, SUM(Amount__c) a' +
					(withCost ? ', SUM(Cost_Amount__c) c' : '') +
					' FROM Time_Entry__c' +
					counted +
					' GROUP BY Project__c, Billable__c',
				binds,
				mode
			)
		) {
			Decimal[] totals = out.get((Id) sum.get('p'));
			Project__c project = byId.get((Id) sum.get('p'));
			if (
				sum.get('b') == true &&
				ProjectBilling.billingType(project) == ProjectBilling.TIME_AND_MATERIALS
			) {
				totals[0] += num(sum.get('a'));
			}
			totals[1] += withCost ? num(sum.get('c')) : 0;
		}
		// Access mode: the caller's, passed as `mode`.
		for (
			AggregateResult sum : (List<AggregateResult>) Database.queryWithBinds(
				'SELECT Project__c p, SUM(Hours__c) h FROM Time_Entry__c' +
					counted +
					' AND Billable__c = TRUE AND Bill_Rate__c = NULL GROUP BY Project__c',
				binds,
				mode
			)
		) {
			Project__c project = byId.get((Id) sum.get('p'));
			if (ProjectBilling.billingType(project) == ProjectBilling.TIME_AND_MATERIALS) {
				out.get(project.Id)[0] += num(sum.get('h')) * num(project.Hourly_Rate__c);
			}
		}
		// Access mode: the caller's, passed as `mode`.
		for (
			AggregateResult sum : (List<AggregateResult>) Database.queryWithBinds(
				'SELECT Project__c p, Billable__c b, SUM(Amount__c) a FROM Project_Expense__c' +
					counted +
					' GROUP BY Project__c, Billable__c',
				binds,
				mode
			)
		) {
			Decimal[] totals = out.get((Id) sum.get('p'));
			totals[0] += sum.get('b') == true ? num(sum.get('a')) : 0;
			totals[1] += withCost ? num(sum.get('a')) : 0;
		}
		for (Project__c project : projects) {
			String type = ProjectBilling.billingType(project);
			if (type == ProjectBilling.FIXED_FEE) {
				out.get(project.Id)[0] +=
					(num(project.Budget_Amount__c) + num(project.Change_Amount__c)) *
					num(project.Percent_Complete__c) /
					100;
			} else if (type == ProjectBilling.RETAINER) {
				out.get(project.Id)[0] +=
					num(project.Retainer_Amount__c) * months(project, through);
			}
		}
		return out;
	}

	/** Retainer months from Start Date's month through the day's month (or Completed Date's). */
	private static Integer months(Project__c project, Date through) {
		if (project.Start_Date__c == null) {
			return 0;
		}
		Date lastDay = project.Completed_Date__c != null &&
			project.Completed_Date__c < through
			? project.Completed_Date__c
			: through;
		return Math.max(0, project.Start_Date__c.toStartOfMonth().monthsBetween(lastDay) + 1);
	}

	/** Inserts new rows and updates existing ones by Month Key (a master-detail is not rewritten). */
	private static void save(List<Project_Revenue__c> rows, AccessLevel mode) {
		Map<String, Project_Revenue__c> byKey = new Map<String, Project_Revenue__c>();
		for (Project_Revenue__c row : rows) {
			byKey.put(row.Month_Key__c, row);
		}
		Set<String> keys = byKey.keySet();
		List<Project_Revenue__c> changed = new List<Project_Revenue__c>();
		// Access mode: the caller's, passed as `mode`.
		for (
			Project_Revenue__c existing : (List<Project_Revenue__c>) Database.queryWithBinds(
				'SELECT Id, Month_Key__c FROM Project_Revenue__c WHERE Month_Key__c IN :keys',
				new Map<String, Object>{ 'keys' => keys },
				mode
			)
		) {
			Project_Revenue__c row = byKey.remove(existing.Month_Key__c);
			row.Id = existing.Id;
			changed.add(
				new Project_Revenue__c(
					Id = existing.Id,
					Method__c = row.Method__c,
					Recognized_Amount__c = row.Recognized_Amount__c,
					Cost_Amount__c = row.Cost_Amount__c,
					Percent_Complete__c = row.Percent_Complete__c
				)
			);
		}
		// Access mode: the caller's, passed as `mode`.
		Database.insert(byKey.values(), true, mode);
		// Access mode: the caller's, passed as `mode`.
		Database.update(changed, true, mode);
	}

	private static String key(Id projectId, Date month) {
		return projectId +
			'-' +
			Datetime.newInstance(month, Time.newInstance(12, 0, 0, 0)).format('yyyy-MM');
	}

	private static Decimal num(Object value) {
		return value == null ? 0 : (Decimal) value;
	}
}
