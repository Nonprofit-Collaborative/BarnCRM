/**
 * Project Management's reporting (ADR-0208 `0208-project-management-module.md` decisions 6 to
 * 8), in user mode: Draft Status Update (R-PM8), utilization by person (R-PM5) and the billable
 * time export (R-PM7). The CSV itself is built in the browser.
 */
public with sharing class ProjectReporting {
	private static final Integer NEXT_DAYS = 14;
	private static final Integer MAX_RANGE_DAYS = 366;

	/** One person's hours in a date range (R-PM5). */
	public class Utilization {
		@AuraEnabled
		public Id userId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Decimal logged = 0;
		@AuraEnabled
		public Decimal billable = 0;
		@AuraEnabled
		public Decimal planned = 0;
		@AuraEnabled
		public Decimal capacity = 0;
	}

	/** Writes a Project Status Update dated today, filled from the project (R-PM8). */
	public static Id draftStatusUpdate(Id projectId) {
		Project__c project = [
			SELECT
				Health__c,
				Health_Reasons__c,
				Tasks__c,
				Tasks_Done__c,
				Actual_Hours__c,
				Start_Date__c
			FROM Project__c
			WHERE Id = :projectId
			WITH USER_MODE
		];
		Date today = Date.today();
		List<Project_Status_Update__c> last = [
			SELECT Report_Date__c
			FROM Project_Status_Update__c
			WHERE Project__c = :projectId
			WITH USER_MODE
			ORDER BY Report_Date__c DESC
			LIMIT 1
		];
		Date since = last.isEmpty() ? project.Start_Date__c : last[0].Report_Date__c;
		List<String> done = new List<String>();
		List<String> next = new List<String>();
		List<String> risks = new List<String>();
		if (String.isNotBlank(project.Health_Reasons__c)) {
			risks.addAll(project.Health_Reasons__c.split('\n'));
		}
		for (Project_Task__c task : [
			SELECT Name, Status__c, Milestone__c, Due_Date__c, Completed_Date__c
			FROM Project_Task__c
			WHERE
				Project__c = :projectId
				AND (Status__c IN ('Done', 'Blocked')
				OR (Status__c != 'Cancelled'
				AND Due_Date__c >= :today
				AND Due_Date__c <= :today.addDays(NEXT_DAYS)))
			WITH USER_MODE
			ORDER BY Due_Date__c NULLS LAST
			LIMIT 1000
		]) {
			String due = task.Due_Date__c == null ? '' : task.Due_Date__c.format();
			if (task.Status__c == Projects.DONE) {
				if (
					since == null ||
					(task.Completed_Date__c != null &&
					task.Completed_Date__c >= since)
				) {
					done.add('- ' + task.Name);
				}
			} else if (task.Status__c == 'Blocked') {
				risks.add(
					BarnHelp.text(
						'Projects',
						'Projects_Update_Blocked',
						new List<Object>{ task.Name }
					)
				);
			}
			if (
				task.Status__c != Projects.DONE &&
				task.Due_Date__c != null &&
				task.Due_Date__c >= today &&
				task.Due_Date__c <= today.addDays(NEXT_DAYS)
			) {
				List<Object> args = new List<Object>{ task.Name, due };
				next.add(
					task.Milestone__c
						? BarnHelp.text('Projects', 'Projects_Update_NextMilestone', args)
						: BarnHelp.text('Projects', 'Projects_Update_NextTask', args)
				);
			}
		}
		Integer total = project.Tasks__c == null ? 0 : project.Tasks__c.intValue();
		Integer finished = project.Tasks_Done__c == null ? 0 : project.Tasks_Done__c.intValue();
		Integer percent = total == 0 ? 0 : Math.round(finished * 100.0 / total);
		String health = String.isBlank(project.Health__c)
			? BarnHelp.text('Projects', 'Projects_Update_NoHealth')
			: project.Health__c;
		Project_Status_Update__c row = new Project_Status_Update__c(
			Project__c = projectId,
			Report_Date__c = today,
			Health__c = project.Health__c,
			Percent_Complete__c = percent,
			Actual_Hours__c = project.Actual_Hours__c,
			Summary__c = BarnHelp.text(
				'Projects',
				'Projects_Update_Summary',
				new List<Object>{ finished, total, percent, health }
			),
			Accomplishments__c = done.isEmpty() ? null : String.join(done, '\n'),
			Next_Steps__c = next.isEmpty() ? null : String.join(next, '\n'),
			Risks__c = risks.isEmpty() ? null : String.join(risks, '\n')
		);
		insert as user row;
		return row.Id;
	}

	/** Logged, billable and planned hours by person in a date range, with their capacity. */
	public static List<Utilization> utilization(Date fromDate, Date toDate) {
		checkRange(fromDate, toDate);
		Map<Id, Utilization> byUser = new Map<Id, Utilization>();
		Integer days = fromDate.daysBetween(toDate) + 1;
		// PM-09 (R-PM14): with Manage resources on, a person's own Weekly Capacity Hours.
		Map<Id, Decimal> weekly = new Map<Id, Decimal>();
		if (ProjectsSettings.resourcesEnabled()) {
			for (Project_Resource__c resource : [
				SELECT User__c, Weekly_Capacity_Hours__c
				FROM Project_Resource__c
				WHERE Weekly_Capacity_Hours__c != NULL
				WITH USER_MODE
				ORDER BY CreatedDate DESC
				LIMIT 2000
			]) {
				weekly.put(resource.User__c, resource.Weekly_Capacity_Hours__c);
			}
		}
		Decimal standard = Decimal.valueOf(ProjectsSettings.weeklyCapacity());
		// Logged hours are counted time only (R-PM10): a blank Status counts; Open, Submitted
		// and Rejected do not.
		for (AggregateResult row : [
			SELECT User__c userId, User__r.Name name, Billable__c billable, SUM(Hours__c) hours
			FROM Time_Entry__c
			WHERE
				User__c != NULL
				AND Date__c >= :fromDate
				AND Date__c <= :toDate
				AND Status__c NOT IN ('Open', 'Submitted', 'Rejected')
			WITH USER_MODE
			GROUP BY User__c, User__r.Name, Billable__c
			LIMIT 2000
		]) {
			Id userId = (Id) row.get('userId');
			Utilization person = person(
				byUser,
				userId,
				(String) row.get('name'),
				capacity(weekly.get(userId), standard, days)
			);
			Decimal hours = (Decimal) row.get('hours');
			person.logged += hours;
			if ((Boolean) row.get('billable')) {
				person.billable += hours;
			}
		}
		for (Project_Assignment__c assignment : [
			SELECT Resource__c, Resource__r.Name, Planned_Hours__c, Start_Date__c, End_Date__c
			FROM Project_Assignment__c
			WHERE
				Resource__c != NULL
				AND Planned_Hours__c > 0
				AND (Start_Date__c = NULL
				OR Start_Date__c <= :toDate)
				AND (End_Date__c = NULL
				OR End_Date__c >= :fromDate)
				AND Project__r.Status__c IN ('Planned', 'Active')
				AND Project__r.Is_Template__c = FALSE
			WITH USER_MODE
			LIMIT 5000
		]) {
			Date starts = assignment.Start_Date__c == null ? fromDate : assignment.Start_Date__c;
			Date ends = assignment.End_Date__c == null ? toDate : assignment.End_Date__c;
			Date overlapStart = starts > fromDate ? starts : fromDate;
			Date overlapEnd = ends < toDate ? ends : toDate;
			if (ends < starts || overlapEnd < overlapStart) {
				continue;
			}
			Decimal share =
				Decimal.valueOf(overlapStart.daysBetween(overlapEnd) + 1) /
				(starts.daysBetween(ends) + 1);
			person(
					byUser,
					assignment.Resource__c,
					assignment.Resource__r.Name,
					capacity(weekly.get(assignment.Resource__c), standard, days)
				)
				.planned += (assignment.Planned_Hours__c * share).setScale(2);
		}
		return byUser.values();
	}

	/**
	 * The billable entries dated in the range, not yet exported unless `includeExported`, as
	 * rows for the CSV; stamps their Exported Date with today (R-PM7). Needs Manage Projects.
	 */
	public static List<Map<String, Object>> exportBillable(
		Date fromDate,
		Date toDate,
		Boolean includeExported
	) {
		Projects.requireManage();
		checkRange(fromDate, toDate);
		List<Time_Entry__c> entries = new List<Time_Entry__c>();
		for (Time_Entry__c entry : [
			SELECT
				Id,
				Name,
				Date__c,
				Hours__c,
				Notes__c,
				Exported_Date__c,
				User__r.Name,
				Task__r.Name,
				Project__r.Name,
				Project__r.Account__r.Name,
				Project__r.Hourly_Rate__c
			FROM Time_Entry__c
			WHERE Billable__c = TRUE AND Date__c >= :fromDate AND Date__c <= :toDate
			WITH USER_MODE
			ORDER BY Project__r.Name, Date__c
			LIMIT 10000
		]) {
			if (includeExported == true || entry.Exported_Date__c == null) {
				entries.add(entry);
			}
		}
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		Date today = Date.today();
		// Only the stamp is saved: a row read with its Project would send the parent link back,
		// and a master-detail field cannot be written on update.
		List<Time_Entry__c> stamps = new List<Time_Entry__c>();
		for (Time_Entry__c entry : entries) {
			Decimal rate = entry.Project__r.Hourly_Rate__c;
			rows.add(
				new Map<String, Object>{
					'entry' => entry.Name,
					'project' => entry.Project__r.Name,
					'client' => entry.Project__r.Account__r?.Name,
					'task' => entry.Task__r?.Name,
					'person' => entry.User__r?.Name,
					'date' => entry.Date__c,
					'hours' => entry.Hours__c,
					'rate' => rate,
					'amount' => rate == null ? null : (rate * entry.Hours__c).setScale(2),
					'notes' => entry.Notes__c
				}
			);
			stamps.add(new Time_Entry__c(Id = entry.Id, Exported_Date__c = today));
		}
		update as user stamps;
		return rows;
	}

	private static Decimal capacity(Decimal own, Decimal standard, Integer days) {
		return ((own == null ? standard : own) * days / 7).setScale(2);
	}

	private static Utilization person(
		Map<Id, Utilization> byUser,
		Id userId,
		String name,
		Decimal capacity
	) {
		Utilization person = byUser.get(userId);
		if (person == null) {
			person = new Utilization();
			person.userId = userId;
			person.name = name;
			person.capacity = capacity;
			byUser.put(userId, person);
		}
		return person;
	}

	private static void checkRange(Date fromDate, Date toDate) {
		if (
			fromDate == null ||
			toDate == null ||
			toDate < fromDate ||
			fromDate.daysBetween(toDate) >= MAX_RANGE_DAYS
		) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Range_Invalid'));
		}
	}
}
