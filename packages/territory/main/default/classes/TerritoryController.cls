/**
 * The Territory Management page's server side (C-40, C-40b; ADR-0205
 * `0205-territory-management-module.md`, decision 8). Thin: territories, rules and members are
 * read here and saved by the page through Lightning Data Service; a run is started, counted and
 * undone here. Answers are plain JSON maps (plan 9.9). Access to this class, given by Territory
 * Admin, is what lets a person use the page.
 */
public with sharing class TerritoryController {
	private static final String CONTEXT = 'TerritoryController';
	/** Runs the page lists. */
	private static final Integer RUNS_SHOWN = 10;
	/** The most a rule's count reads. */
	private static final Integer COUNT_CEILING = 50000;

	/** Territories with their rules and members, the latest runs, and whether one is busy. */
	@AuraEnabled
	public static Map<String, Object> getPage() {
		try {
			List<Map<String, Object>> territories = new List<Map<String, Object>>();
			for (Territory__c territory : [
				SELECT
					Id,
					Name,
					Active__c,
					Priority__c,
					Routing__c,
					Owner_User__c,
					Owner_User__r.Name,
					Description__c,
					(
						SELECT Id, Name, Applies_To__c, Filter_JSON__c, Summary__c, Active__c
						FROM Rules__r
						ORDER BY Name
					),
					(
						SELECT Id, User__c, User__r.Name, User__r.IsActive, Capacity__c, Active__c
						FROM Members__r
						ORDER BY Name
					)
				FROM Territory__c
				WITH USER_MODE
				ORDER BY Priority__c, Name
				LIMIT 500
			]) {
				territories.add(territoryJson(territory));
			}
			List<Territory_Run__c> runs = [
				SELECT
					Id,
					Name,
					Mode__c,
					Only_Unassigned__c,
					Status__c,
					Checked__c,
					Changes__c,
					Failed__c,
					Summary_JSON__c,
					Data_Job_Id__c,
					Message__c,
					CreatedDate,
					CreatedBy.Name,
					Completed_At__c
				FROM Territory_Run__c
				WITH USER_MODE
				ORDER BY CreatedDate DESC
				LIMIT :RUNS_SHOWN
			];
			return new Map<String, Object>{
				'territories' => territories,
				'runs' => runsJson(runs),
				'busy' => TerritoryRunBatch.busy(),
				'maxRules' => TerritoryRunBatch.MAX_RULES
			};
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.getPage', true);
		}
	}

	/** Starts a Preview or an Assign run of every kind with active rules. Returns the run's Id. */
	@AuraEnabled
	public static Id startRun(String mode, Boolean onlyUnassigned) {
		try {
			if (mode != TerritoryRunBatch.MODE_PREVIEW && mode != TerritoryRunBatch.MODE_ASSIGN) {
				throw new TerritoryRunBatch.TerritoryException(
					BarnHelp.text('Territory', 'Territory_Error_NothingToRun')
				);
			}
			if (TerritoryRunBatch.busy()) {
				throw new TerritoryRunBatch.TerritoryException(
					BarnHelp.text('Territory', 'Territory_Error_Busy')
				);
			}
			List<String> kinds = TerritoryRunBatch.kindsToRun();
			if (kinds.isEmpty()) {
				throw new TerritoryRunBatch.TerritoryException(
					BarnHelp.text('Territory', 'Territory_Error_NothingToRun')
				);
			}
			return TerritoryRunBatch.launch(mode, onlyUnassigned == true, kinds);
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.startRun', true);
		}
	}

	/** How many records of a kind a rule's filter matches now, counting at most 50,000. */
	@AuraEnabled
	public static Integer countRule(String appliesTo, String filterJson) {
		try {
			if (!TerritoryRunBatch.ALL_KINDS.contains(appliesTo)) {
				throw new TerritoryRunBatch.TerritoryException(
					BarnHelp.text('Territory', 'Territory_Error_NothingToRun')
				);
			}
			return TerritoryRunBatch.countMatching(appliesTo, filterJson, COUNT_CEILING);
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.countRule', false);
		}
	}

	/** Starts the undo of an Assign run's Data job: every change it saved is put back. */
	@AuraEnabled
	public static Id undoRun(Id runId) {
		try {
			List<Territory_Run__c> runs = [
				SELECT Data_Job_Id__c
				FROM Territory_Run__c
				WHERE Id = :runId
				WITH USER_MODE
				LIMIT 1
			];
			if (runs.isEmpty() || String.isBlank(runs[0].Data_Job_Id__c)) {
				throw new TerritoryRunBatch.TerritoryException(
					BarnHelp.text('Territory', 'Territory_Error_NoJob')
				);
			}
			Id jobId = runs[0].Data_Job_Id__c;
			return ImportUndoService.start(jobId, ImportUndoService.preview(jobId).getTotal());
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.undoRun', true);
		}
	}

	private static Map<String, Object> territoryJson(Territory__c territory) {
		List<Map<String, Object>> rules = new List<Map<String, Object>>();
		for (Territory_Rule__c rule : territory.Rules__r) {
			rules.add(
				new Map<String, Object>{
					'id' => rule.Id,
					'name' => rule.Name,
					'appliesTo' => rule.Applies_To__c,
					'filterJson' => rule.Filter_JSON__c,
					'summary' => rule.Summary__c,
					'active' => rule.Active__c
				}
			);
		}
		List<Map<String, Object>> members = new List<Map<String, Object>>();
		for (Territory_Member__c member : territory.Members__r) {
			members.add(
				new Map<String, Object>{
					'id' => member.Id,
					'userId' => member.User__c,
					'userName' => member.User__r?.Name,
					'userActive' => member.User__r?.IsActive,
					'capacity' => member.Capacity__c,
					'active' => member.Active__c
				}
			);
		}
		return new Map<String, Object>{
			'id' => territory.Id,
			'name' => territory.Name,
			'active' => territory.Active__c,
			'priority' => territory.Priority__c,
			'routing' => territory.Routing__c,
			'ownerId' => territory.Owner_User__c,
			'ownerName' => territory.Owner_User__r?.Name,
			'description' => territory.Description__c,
			'rules' => rules,
			'members' => members
		};
	}

	/** Each run, with its Data job's status read in system mode (the job is bookkeeping). */
	private static List<Map<String, Object>> runsJson(List<Territory_Run__c> runs) {
		Set<Id> jobIds = new Set<Id>();
		for (Territory_Run__c run : runs) {
			if (String.isNotBlank(run.Data_Job_Id__c)) {
				jobIds.add(run.Data_Job_Id__c);
			}
		}
		Map<Id, Import_Batch__c> jobs = new Map<Id, Import_Batch__c>(
			[SELECT Id, Status__c FROM Import_Batch__c WHERE Id IN :jobIds WITH SYSTEM_MODE]
		);
		List<Map<String, Object>> shown = new List<Map<String, Object>>();
		for (Territory_Run__c run : runs) {
			Import_Batch__c job = String.isBlank(run.Data_Job_Id__c)
				? null
				: jobs.get(run.Data_Job_Id__c);
			shown.add(
				new Map<String, Object>{
					'id' => run.Id,
					'name' => run.Name,
					'mode' => run.Mode__c,
					'onlyUnassigned' => run.Only_Unassigned__c,
					'status' => run.Status__c,
					'checked' => run.Checked__c,
					'changes' => run.Changes__c,
					'failed' => run.Failed__c,
					'summaryJson' => run.Summary_JSON__c,
					'message' => run.Message__c,
					'createdDate' => run.CreatedDate,
					'createdBy' => run.CreatedBy?.Name,
					'completedAt' => run.Completed_At__c,
					'jobStatus' => job?.Status__c,
					'canUndo' => job != null &&
					(job.Status__c == ImportBatchService.STATUS_COMPLETE ||
					job.Status__c == ImportBatchService.STATUS_FAILED)
				}
			);
		}
		return shown;
	}
}
