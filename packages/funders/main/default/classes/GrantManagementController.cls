/**
 * The grant management cards on a grant's page (F-10 to F-13, canonical model R-GQ7, R-GQ8,
 * R-BL2, R-GN12): Checklist, Documents, Budget and Renewals.
 *
 * Thin by design (plan Section 9.9): plain maps out, the arithmetic in the browser module
 * `grantManagementModel`, the rules in `GrantManagementService`. Everything runs as the person.
 */
public with sharing class GrantManagementController {
	private static final String CONTEXT = 'GrantManagementController';
	private static final Integer MAX_ROWS = 200;

	/** The Checklist card: the grant's Task requirements. Cached; the card refreshes it after a save. */
	@AuraEnabled(cacheable=true)
	public static Map<String, Object> getChecklist(Id grantId) {
		try {
			List<Map<String, Object>> tasks = new List<Map<String, Object>>();
			for (Grant_Requirement__c task : [
				SELECT Id, Name, Status__c, Due_Date__c, Assigned_To__r.Name
				FROM Grant_Requirement__c
				WHERE Grant__c = :grantId AND Type__c = :GrantRequirementService.TYPE_TASK
				WITH USER_MODE
				ORDER BY Due_Date__c, Name
				LIMIT :MAX_ROWS
			]) {
				tasks.add(
					new Map<String, Object>{
						'id' => task.Id,
						'name' => task.Name,
						'status' => task.Status__c,
						'done' => !GrantRequirementService.isOpen(task.Status__c),
						'dueDate' => task.Due_Date__c,
						'assignedTo' => task.Assigned_To__r?.Name
					}
				);
			}
			return new Map<String, Object>{
				'tasks' => tasks,
				'canEdit' => Schema.SObjectType.Grant_Requirement__c.isUpdateable(),
				'canAdd' => Schema.SObjectType.Grant_Requirement__c.isCreateable()
			};
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getChecklist', grantId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Manage_LoadFailed'));
		}
	}

	/** Add Checklist Tasks: how many were added. */
	@AuraEnabled
	public static Integer addChecklistTasks(Id grantId) {
		try {
			return GrantManagementService.addChecklistTasks(grantId);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.addChecklistTasks', grantId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
		}
	}

	/** Ticks a task done, or open again. */
	@AuraEnabled
	public static void setTaskDone(Id requirementId, Boolean done) {
		try {
			GrantManagementService.setTaskDone(requirementId, done);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.setTaskDone', requirementId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
		}
	}

	/** The Documents card: LOI, application and report requirements with their files (R-GQ8). */
	@AuraEnabled
	public static Map<String, Object> getDocuments(Id grantId) {
		try {
			Map<Id, Map<String, Object>> byId = new Map<Id, Map<String, Object>>();
			for (Grant_Requirement__c document : [
				SELECT Id, Name, Type__c, Status__c, Due_Date__c, Submitted_Date__c
				FROM Grant_Requirement__c
				WHERE Grant__c = :grantId AND Type__c IN :GrantRequirementService.DOCUMENT_TYPES
				WITH USER_MODE
				ORDER BY Due_Date__c, Name
				LIMIT :MAX_ROWS
			]) {
				byId.put(
					document.Id,
					new Map<String, Object>{
						'id' => document.Id,
						'name' => document.Name,
						'type' => document.Type__c,
						'status' => document.Status__c,
						'dueDate' => document.Due_Date__c,
						'submittedDate' => document.Submitted_Date__c,
						'fileCount' => 0
					}
				);
			}
			if (!byId.isEmpty()) {
				for (ContentDocumentLink link : [
					SELECT
						LinkedEntityId,
						ContentDocumentId,
						ContentDocument.Title,
						ContentDocument.FileExtension,
						ContentDocument.LastModifiedDate,
						ContentDocument.LatestPublishedVersion.VersionNumber
					FROM ContentDocumentLink
					WHERE LinkedEntityId IN :byId.keySet()
					WITH USER_MODE
					ORDER BY ContentDocument.LastModifiedDate DESC
					LIMIT 1000
				]) {
					Map<String, Object> document = byId.get(link.LinkedEntityId);
					document.put('fileCount', (Integer) document.get('fileCount') + 1);
					if (!document.containsKey('fileId')) {
						document.put('fileId', link.ContentDocumentId);
						document.put('fileTitle', link.ContentDocument.Title);
						document.put('fileExtension', link.ContentDocument.FileExtension);
						document.put(
							'fileVersion',
							link.ContentDocument.LatestPublishedVersion?.VersionNumber
						);
						document.put('fileDate', link.ContentDocument.LastModifiedDate);
					}
				}
			}
			return new Map<String, Object>{
				'documents' => byId.values(),
				'types' => GrantRequirementService.DOCUMENT_TYPES,
				'canUpload' => Schema.SObjectType.Grant_Requirement__c.isUpdateable(),
				'canCreate' => Schema.SObjectType.Grant_Requirement__c.isCreateable()
			};
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getDocuments', grantId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Manage_LoadFailed'));
		}
	}

	/** The Budget card: each line with its Spent entries summed, and the grant's amounts (R-BL2). */
	@AuraEnabled
	public static Map<String, Object> getBudget(Id grantId) {
		try {
			Map<String, Object> budget = new Map<String, Object>{
				'canCreate' => Schema.SObjectType.Grant_Budget_Line__c.isCreateable()
			};
			for (Grant__c grant : [
				SELECT Amount_Requested__c, Amount_Awarded__c, Restricted__c
				FROM Grant__c
				WHERE Id = :grantId
				WITH USER_MODE
				LIMIT 1
			]) {
				budget.put('amountRequested', grant.Amount_Requested__c);
				budget.put('amountAwarded', grant.Amount_Awarded__c);
				budget.put('restricted', grant.Restricted__c);
			}
			Map<Id, Decimal> spentByLine = new Map<Id, Decimal>();
			for (AggregateResult row : [
				SELECT Budget_Line__c line, SUM(Amount__c) total
				FROM Grant_Fund_Entry__c
				WHERE Grant__c = :grantId AND Type__c = 'Spent'
				WITH USER_MODE
				GROUP BY Budget_Line__c
			]) {
				spentByLine.put((Id) row.get('line'), (Decimal) row.get('total'));
			}
			List<Map<String, Object>> lines = new List<Map<String, Object>>();
			for (Grant_Budget_Line__c line : [
				SELECT Id, Name, Amount_Requested__c, Amount_Awarded__c
				FROM Grant_Budget_Line__c
				WHERE Grant__c = :grantId
				WITH USER_MODE
				ORDER BY Name
				LIMIT :MAX_ROWS
			]) {
				lines.add(
					new Map<String, Object>{
						'id' => line.Id,
						'name' => line.Name,
						'requested' => line.Amount_Requested__c,
						'awarded' => line.Amount_Awarded__c,
						'spent' => spentByLine.get(line.Id)
					}
				);
				spentByLine.remove(line.Id);
			}
			Decimal unassigned = 0;
			for (Decimal spent : spentByLine.values()) {
				unassigned += spent == null ? 0 : spent;
			}
			budget.put('lines', lines);
			budget.put('unassignedSpent', unassigned);
			return budget;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getBudget', grantId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Manage_LoadFailed'));
		}
	}

	/** The Renewals card: the chain across years and whether Start Renewal is offered (R-GN12). Cached. */
	@AuraEnabled(cacheable=true)
	public static Map<String, Object> getRenewals(Id grantId) {
		try {
			List<Map<String, Object>> chain = new List<Map<String, Object>>();
			Boolean renewed = false;
			Grant__c current;
			for (Grant__c grant : GrantManagementService.renewalChain(grantId)) {
				chain.add(
					new Map<String, Object>{
						'id' => grant.Id,
						'name' => grant.Name,
						'stage' => grant.Stage__c,
						'startDate' => grant.Award_Start_Date__c,
						'endDate' => grant.Award_End_Date__c,
						'requested' => grant.Amount_Requested__c,
						'awarded' => grant.Amount_Awarded__c,
						'current' => grant.Id == grantId
					}
				);
				renewed = renewed || current != null;
				if (grant.Id == grantId) {
					current = grant;
				}
			}
			return new Map<String, Object>{
				'chain' => chain,
				'canStart' => current != null &&
				!renewed &&
				current.Stage__c == GrantService.STAGE_AWARDED &&
				Schema.SObjectType.Grant__c.isCreateable()
			};
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getRenewals', grantId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Manage_LoadFailed'));
		}
	}

	/** Start Renewal: the new grant. */
	@AuraEnabled
	public static Id startRenewal(Id grantId) {
		try {
			return GrantManagementService.startRenewal(grantId);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.startRenewal', grantId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
		}
	}
}
