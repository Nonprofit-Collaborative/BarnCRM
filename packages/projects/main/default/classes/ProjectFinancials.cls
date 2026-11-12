/**
 * The Financials card's figures (PM-11; ADR-NEXT `NEXT-projects-psa.md` decision 7; canonical
 * model R-PM21), worked out on demand in user mode: budget (Budget Amount plus approved changes),
 * revenue and cost to date (as R-PM19 earns them, through today), invoiced (Sent and Paid totals)
 * and the stored months. Cost is read only by those who can read cost (Projects Admin); margin,
 * unbilled and the open month are worked out by `c/projectsBillingModel`.
 */
public with sharing class ProjectFinancials {
	/** The card's figures, or only `enabled` false when financials are off. */
	public static Map<String, Object> card(Id projectId) {
		if (!ProjectsSettings.revenueEnabled()) {
			return new Map<String, Object>{ 'enabled' => false };
		}
		Boolean withCost =
			Schema.SObjectType.Time_Entry__c.fields.Cost_Amount__c.isAccessible() &&
			Schema.SObjectType.Project_Revenue__c.fields.Cost_Amount__c.isAccessible();
		Project__c project = [
			SELECT
				Id,
				Billing_Type__c,
				Budget_Amount__c,
				Change_Amount__c,
				Percent_Complete__c,
				Retainer_Amount__c,
				Hourly_Rate__c,
				Start_Date__c,
				Completed_Date__c
			FROM Project__c
			WHERE Id = :projectId
			WITH USER_MODE
		];
		String type = ProjectBilling.billingType(project);
		Decimal[] earned = type == ProjectBilling.NOT_BILLED
			? new List<Decimal>{ 0, 0 }
			: ProjectRevenue.earned(
						new List<Project__c>{ project },
						Date.today(),
						withCost,
						AccessLevel.USER_MODE
					)
					.get(projectId);
		AggregateResult invoiced = [
			SELECT SUM(Total__c) total
			FROM Project_Invoice__c
			WHERE Project__c = :projectId AND Status__c IN ('Sent', 'Paid')
			WITH USER_MODE
		];
		List<Map<String, Object>> months = new List<Map<String, Object>>();
		for (
			Project_Revenue__c row : (List<Project_Revenue__c>) Database.queryWithBinds(
				'SELECT Month__c, Recognized_Amount__c, Percent_Complete__c' +
					(withCost ? ', Cost_Amount__c' : '') +
					' FROM Project_Revenue__c WHERE Project__c = :projectId' +
					' ORDER BY Month__c LIMIT 240',
				new Map<String, Object>{ 'projectId' => projectId },
				AccessLevel.USER_MODE
			)
		) {
			months.add(
				new Map<String, Object>{
					'month' => row.Month__c,
					'recognized' => row.Recognized_Amount__c,
					'cost' => withCost ? row.Cost_Amount__c : null,
					'percent' => row.Percent_Complete__c
				}
			);
		}
		// Change Amount sums only Approved change requests, so it is 0 for a project with none.
		Decimal budget = project.Budget_Amount__c == null
			? null
			: project.Budget_Amount__c +
			  (project.Change_Amount__c == null ? 0 : project.Change_Amount__c);
		return new Map<String, Object>{
			'enabled' => true,
			'canManage' => Projects.canManage(),
			'withCost' => withCost,
			'billingType' => type,
			'budget' => budget,
			'revenue' => earned[0],
			'cost' => withCost ? earned[1] : null,
			'invoiced' => invoiced.get('total') == null ? 0 : invoiced.get('total'),
			'months' => months
		};
	}
}
