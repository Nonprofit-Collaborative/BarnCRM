/**
 * Grant management (F-10, F-13; canonical model R-GQ7 and R-GN12; ADR-NEXT funders grant finder
 * and grant management): checklist tasks by stage, the renewal requirement, Start Renewal and the
 * renewal history.
 *
 * The two automations write in system mode, like the reminder stamps (R-GQ3): they set Checklist
 * Item, which only Funders Admin may edit, on a grant the person is already saving. Everything a
 * person starts from a card runs as that person.
 */
public with sharing class GrantManagementService {
	/** R-GQ7: a task of a grant with no deadline is due this many days from today. */
	public static final Integer NO_DEADLINE_DAYS = 14;
	/** R-GN12: the most grants the renewal history follows. */
	public static final Integer MAX_CHAIN = 20;
	private static final Integer MAX_ITEMS = 200;

	/** The grant fields Start Renewal copies to the next grant (R-GN12). */
	private static final List<String> COPIED = new List<String>{
		'Funder__c',
		'Funder_Contact__c',
		'Purpose__c',
		'Program_Id__c',
		'Fund_Id__c',
		'Funding_Source__c',
		'Restricted__c',
		'Payment_Frequency__c',
		'Assistance_Listing_Number__c',
		'Federal_Agency__c',
		'Indirect_Cost_Rate__c',
		'Match_Required__c'
	};

	/** R-GQ7: each grant created at, or moved to, a stage gets that stage's checklist tasks. */
	public static void addTasksOnStageChange(List<Grant__c> grants, Map<Id, Grant__c> oldById) {
		List<Grant__c> moved = new List<Grant__c>();
		for (Grant__c grant : grants) {
			if (oldById == null || oldById.get(grant.Id).Stage__c != grant.Stage__c) {
				moved.add(grant);
			}
		}
		if (!moved.isEmpty()) {
			insert as system checklistTasks(moved);
		}
	}

	/**
	 * Add Checklist Tasks on the Checklist card: the tasks the grant's current stage still needs,
	 * for a person who can create requirements.
	 *
	 * @return how many were added
	 */
	public static Integer addChecklistTasks(Id grantId) {
		List<Grant__c> grants = [
			SELECT Id, Stage__c, Application_Deadline__c
			FROM Grant__c
			WHERE Id = :grantId
			WITH USER_MODE
			LIMIT 1
		];
		if (grants.isEmpty() || !Schema.SObjectType.Grant_Requirement__c.isCreateable()) {
			return 0;
		}
		List<Grant_Requirement__c> tasks = checklistTasks(grants);
		insert as system tasks;
		return tasks.size();
	}

	/** The tasks the grants' current stages still need, not inserted (R-GQ7). */
	@TestVisible
	private static List<Grant_Requirement__c> checklistTasks(List<Grant__c> grants) {
		Set<String> stages = new Set<String>();
		Set<Id> grantIds = new Set<Id>();
		for (Grant__c grant : grants) {
			stages.add(grant.Stage__c);
			grantIds.add(grant.Id);
		}
		List<Grant_Requirement__c> tasks = new List<Grant_Requirement__c>();
		List<Grant_Checklist_Item__c> items = [
			SELECT Id, Name, Stage__c, Days_Before_Deadline__c, Assigned_To__c, Instructions__c
			FROM Grant_Checklist_Item__c
			WHERE Active__c = TRUE AND Stage__c IN :stages
			WITH SYSTEM_MODE
			ORDER BY Days_Before_Deadline__c DESC NULLS LAST, Name
			LIMIT :MAX_ITEMS
		];
		if (items.isEmpty()) {
			return tasks;
		}
		Set<String> existing = new Set<String>();
		for (Grant_Requirement__c task : [
			SELECT Grant__c, Checklist_Item__c
			FROM Grant_Requirement__c
			WHERE Grant__c IN :grantIds AND Checklist_Item__c IN :items
			WITH SYSTEM_MODE
		]) {
			existing.add('' + task.Grant__c + task.Checklist_Item__c);
		}
		Date today = Date.today();
		for (Grant__c grant : grants) {
			for (Grant_Checklist_Item__c item : items) {
				if (
					item.Stage__c == grant.Stage__c && !existing.contains('' + grant.Id + item.Id)
				) {
					tasks.add(
						new Grant_Requirement__c(
							Grant__c = grant.Id,
							Name = item.Name,
							Type__c = GrantRequirementService.TYPE_TASK,
							Status__c = GrantRequirementService.STATUS_NOT_STARTED,
							Due_Date__c = dueDate(
								grant.Application_Deadline__c,
								item.Days_Before_Deadline__c,
								today
							),
							Assigned_To__c = item.Assigned_To__c,
							Instructions__c = item.Instructions__c,
							Checklist_Item__c = item.Id
						)
					);
				}
			}
		}
		return tasks;
	}

	/** R-GQ7: the days before the deadline, never before today; no deadline, 14 days out. */
	@TestVisible
	private static Date dueDate(Date deadline, Decimal daysBefore, Date today) {
		if (deadline == null) {
			return today.addDays(NO_DEADLINE_DAYS);
		}
		Date due = deadline.addDays(daysBefore == null ? 0 : -daysBefore.intValue());
		return due < today ? today : due;
	}

	/** Ticks a task done, or open again, as the person (the Checklist card). */
	public static void setTaskDone(Id requirementId, Boolean done) {
		update as user new Grant_Requirement__c(
			Id = requirementId,
			Status__c = done == true
				? GrantRequirementService.STATUS_DONE
				: GrantRequirementService.STATUS_NOT_STARTED
		);
	}

	/**
	 * R-GN12: an Awarded, Renewable grant with an Award End Date has one open Renewal requirement,
	 * due the renewal lead time before the end date and never before today. Runs when one of
	 * those changes; a grant that already has a renewal gets none.
	 */
	public static void syncRenewals(List<Grant__c> grants, Map<Id, Grant__c> oldById) {
		Map<Id, Grant__c> wanted = new Map<Id, Grant__c>();
		for (Grant__c grant : grants) {
			Grant__c old = oldById == null ? null : oldById.get(grant.Id);
			Boolean changed =
				old == null ||
				old.Renewable__c != grant.Renewable__c ||
				old.Stage__c != grant.Stage__c ||
				old.Award_End_Date__c != grant.Award_End_Date__c;
			if (
				changed &&
				grant.Renewable__c &&
				grant.Stage__c == GrantService.STAGE_AWARDED &&
				grant.Award_End_Date__c != null
			) {
				wanted.put(grant.Id, grant);
			}
		}
		if (wanted.isEmpty()) {
			return;
		}
		for (Grant__c renewal : [
			SELECT Renewal_Of__c
			FROM Grant__c
			WHERE Renewal_Of__c IN :wanted.keySet()
			WITH SYSTEM_MODE
		]) {
			wanted.remove(renewal.Renewal_Of__c);
		}
		Map<Id, Grant_Requirement__c> openByGrant = new Map<Id, Grant_Requirement__c>();
		for (Grant_Requirement__c open : openRenewals(wanted.keySet())) {
			openByGrant.put(open.Grant__c, open);
		}
		Integer lead = FundersSettings.renewalLeadDays();
		Date today = Date.today();
		List<Grant_Requirement__c> changes = new List<Grant_Requirement__c>();
		for (Grant__c grant : wanted.values()) {
			Date due = grant.Award_End_Date__c.addDays(-lead);
			due = due < today ? today : due;
			Grant_Requirement__c open = openByGrant.get(grant.Id);
			if (open == null) {
				changes.add(
					new Grant_Requirement__c(
						Grant__c = grant.Id,
						Name = BarnHelp.text('Funders', 'Funders_Renewal_RequirementName'),
						Type__c = GrantRequirementService.TYPE_RENEWAL,
						Status__c = GrantRequirementService.STATUS_NOT_STARTED,
						Due_Date__c = due
					)
				);
			} else if (open.Due_Date__c != due) {
				changes.add(new Grant_Requirement__c(Id = open.Id, Due_Date__c = due));
			}
		}
		upsert as system changes;
	}

	/**
	 * Start Renewal (R-GN12), as the person: the next cycle's grant at Prospect, copied from this
	 * one with its budget lines, the award as the new request; the open Renewal requirement Done.
	 *
	 * @return the new grant
	 */
	public static Id startRenewal(Id grantId) {
		Grant__c grant = [
			SELECT
				Id,
				Name,
				Funder__c,
				Funder_Contact__c,
				Purpose__c,
				Program_Id__c,
				Fund_Id__c,
				Funding_Source__c,
				Restricted__c,
				Payment_Frequency__c,
				Assistance_Listing_Number__c,
				Federal_Agency__c,
				Indirect_Cost_Rate__c,
				Match_Required__c,
				Amount_Requested__c,
				Amount_Awarded__c,
				(
					SELECT Name, Amount_Requested__c, Amount_Awarded__c
					FROM Budget_Lines__r
					ORDER BY Name
					LIMIT 200
				)
			FROM Grant__c
			WHERE Id = :grantId
			WITH USER_MODE
			LIMIT 1
		];
		Grant__c next = new Grant__c(
			Name = grant.Name,
			Stage__c = GrantService.STAGE_PROSPECT,
			Renewable__c = true,
			Renewal_Of__c = grant.Id,
			Amount_Requested__c = grant.Amount_Awarded__c != null
				? grant.Amount_Awarded__c
				: grant.Amount_Requested__c
		);
		for (String field : COPIED) {
			next.put(field, grant.get(field));
		}
		insert as user next;
		List<Grant_Budget_Line__c> lines = new List<Grant_Budget_Line__c>();
		for (Grant_Budget_Line__c line : grant.Budget_Lines__r) {
			lines.add(
				new Grant_Budget_Line__c(
					Grant__c = next.Id,
					Name = line.Name,
					Amount_Requested__c = line.Amount_Awarded__c != null
						? line.Amount_Awarded__c
						: line.Amount_Requested__c
				)
			);
		}
		insert as user lines;
		// The renewal requirement is the automation's bookkeeping, closed like it was opened.
		List<Grant_Requirement__c> open = openRenewals(new Set<Id>{ grant.Id });
		for (Grant_Requirement__c requirement : open) {
			requirement.Status__c = GrantRequirementService.STATUS_DONE;
		}
		update as system open;
		return next.Id;
	}

	/** The open Renewal requirements of the grants, read like the automation that keeps them. */
	private static List<Grant_Requirement__c> openRenewals(Set<Id> grantIds) {
		return [
			SELECT Id, Grant__c, Due_Date__c
			FROM Grant_Requirement__c
			WHERE
				Grant__c IN :grantIds
				AND Type__c = :GrantRequirementService.TYPE_RENEWAL
				AND Status__c IN :GrantRequirementService.OPEN_STATUSES
			WITH SYSTEM_MODE
		];
	}

	/**
	 * R-GN12: every grant in the renewal chain of this one, the first first, at most MAX_CHAIN,
	 * read as the person. A loop of links typed by hand stops where it repeats.
	 */
	public static List<Grant__c> renewalChain(Id grantId) {
		Id first = grantId;
		Set<Id> seen = new Set<Id>{ grantId };
		for (Integer step = 0; step < MAX_CHAIN; step++) {
			List<Grant__c> rows = [
				SELECT Renewal_Of__c
				FROM Grant__c
				WHERE Id = :first
				WITH USER_MODE
				LIMIT 1
			];
			if (
				rows.isEmpty() ||
				rows[0].Renewal_Of__c == null ||
				seen.contains(rows[0].Renewal_Of__c)
			) {
				break;
			}
			first = rows[0].Renewal_Of__c;
			seen.add(first);
		}
		List<Id> ordered = new List<Id>{ first };
		Set<Id> inChain = new Set<Id>{ first };
		Set<Id> frontier = new Set<Id>{ first };
		while (!frontier.isEmpty() && ordered.size() < MAX_CHAIN) {
			Set<Id> nextFrontier = new Set<Id>();
			for (Grant__c renewal : [
				SELECT Id
				FROM Grant__c
				WHERE Renewal_Of__c IN :frontier
				WITH USER_MODE
				ORDER BY CreatedDate
				LIMIT :MAX_CHAIN
			]) {
				if (inChain.add(renewal.Id) && ordered.size() < MAX_CHAIN) {
					ordered.add(renewal.Id);
					nextFrontier.add(renewal.Id);
				}
			}
			frontier = nextFrontier;
		}
		Map<Id, Grant__c> byId = new Map<Id, Grant__c>(
			[
				SELECT
					Id,
					Name,
					Stage__c,
					Award_Start_Date__c,
					Award_End_Date__c,
					Amount_Requested__c,
					Amount_Awarded__c
				FROM Grant__c
				WHERE Id IN :ordered
				WITH USER_MODE
			]
		);
		List<Grant__c> chain = new List<Grant__c>();
		for (Id id : ordered) {
			if (byId.containsKey(id)) {
				chain.add(byId.get(id));
			}
		}
		return chain;
	}
}
