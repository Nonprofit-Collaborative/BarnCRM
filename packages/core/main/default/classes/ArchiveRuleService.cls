/**
 * Archive rules (canonical model R-SQ18, ADR-0240 archive rules and big object archive): saved Find
 * queries whose document carries the `archive` key, set up, previewed and run from the Archive
 * Rules panel, and run on their schedule by the nightly run's Archive Rules step.
 *
 * Saved queries are read and written as the person. Only people holding Manage BarnCRM Settings
 * or Manage Archive (BarnCRM Archive Admin), with Find and Export Records and Bulk Delete Records,
 * may use it. A manual run is the bulk delete
 * preview and typed count (R-BD2, R-BD4); a schedule is turned on with the same typed count once.
 */
public with sharing class ArchiveRuleService {
	private static final Integer RUNS_SHOWN = 20;
	private static final Integer QUERIES_READ = 500;
	private static final String CONTEXT = 'ArchiveRuleService';
	/**
	 * The custom permissions a person needs to set up and run archive rules; Manage Archive
	 * (BarnCRM Archive Admin, AR-14) may stand in for the first.
	 */
	private static final List<String> RUN_PERMISSIONS = new List<String>{
		DataJobs.EVERYONE_PERMISSION,
		'Find_And_Export_Records',
		BulkDeleteController.PERMISSION
	};

	/** A saved query as the panel lists it. */
	public class RuleView {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String objectName;
		@AuraEnabled
		public String ownerName;
		@AuraEnabled
		public Boolean mine;
		@AuraEnabled
		public ArchiveRules.Rule rule;
		@AuraEnabled
		public String destinationLabel;
		@AuraEnabled
		public Date nextRun;
		/** True while the rule's last big object run is still going: Run Now waits for it. */
		@AuraEnabled
		public Boolean running;
	}

	/** One big object run or restore as the panel lists it. */
	public class RunView {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String ruleName;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Boolean running;
		@AuraEnabled
		public Datetime startedAt;
		@AuraEnabled
		public Integer moved;
		@AuraEnabled
		public Integer leftOut;
		@AuraEnabled
		public String log;
	}

	/** The panel. */
	public class Panel {
		@AuraEnabled
		public List<RuleView> rules = new List<RuleView>();
		@AuraEnabled
		public List<RuleView> candidates = new List<RuleView>();
		@AuraEnabled
		public List<ArchiveDestinations.Choice> destinations = new List<ArchiveDestinations.Choice>();
		@AuraEnabled
		public List<RunView> runs = new List<RunView>();
		@AuraEnabled
		public Integer archivedCount;
		@AuraEnabled
		public Integer cap = BigObjectArchiveJob.CAP;
		@AuraEnabled
		public Integer warnAt = BigObjectArchiveJob.WARN_AT;
		@AuraEnabled
		public Integer runLimit;
	}

	/** The custom permission BarnCRM Archive Admin grants (D-223, ADR-0240 amendment AR-14). */
	public static final String ARCHIVE_PERMISSION = 'Manage_Archive';

	/**
	 * Whether the running user is an archive administrator: a BarnCRM Admin (Manage BarnCRM
	 * Settings) or a holder of BarnCRM Archive Admin (Manage Archive).
	 */
	public static Boolean archiveAdmin() {
		return FeatureManagement.checkPermission(DataJobs.EVERYONE_PERMISSION) ||
			FeatureManagement.checkPermission(ARCHIVE_PERMISSION);
	}

	/** Whether the running user may use archive rules: an archive administrator who may bulk delete. */
	public static Boolean allowed() {
		return archiveAdmin() &&
			FeatureManagement.checkPermission('Find_And_Export_Records') &&
			FeatureManagement.checkPermission(BulkDeleteController.PERMISSION);
	}

	public static Panel page() {
		requireAllowed();
		Panel result = new Panel();
		result.runLimit = BulkDeleteService.runLimit();
		result.archivedCount = BigObjectArchiveJob.archivedCount();
		result.destinations = ArchiveDestinations.choices();
		Id me = UserInfo.getUserId();
		Date today = OrgDate.today();
		Set<String> running = BigObjectArchiveJob.running('archive', 'savedQueryId');
		// A rule whose backup is still being saved is running too (AR-15).
		running.addAll(ArchiveBackupGate.waiting());
		for (Saved_Query__c query : [
			SELECT Id, Name, Object_Name__c, OwnerId, Owner.Name, Query_JSON__c
			FROM Saved_Query__c
			WITH USER_MODE
			ORDER BY Name
			LIMIT :QUERIES_READ
		]) {
			RuleView view = new RuleView();
			view.id = query.Id;
			view.name = query.Name;
			view.objectName = query.Object_Name__c;
			view.ownerName = query.Owner?.Name;
			view.mine = query.OwnerId == me;
			view.rule = ArchiveRules.of(query.Query_JSON__c);
			if (view.rule != null) {
				view.destinationLabel = ArchiveDestinations.labelOf(view.rule.destination);
				view.nextRun = ArchiveRules.nextDue(view.rule, today);
				view.running = running.contains(view.id);
				result.rules.add(view);
			} else if (view.mine) {
				result.candidates.add(view);
			}
		}
		result.runs = runs();
		return result;
	}

	/** The person's own big object runs and restores, newest first. */
	public static List<RunView> runs() {
		List<RunView> result = new List<RunView>();
		for (
			Import_Batch__c job : DataJobs.read(
				'Id, Name, Status__c, Started_At__c, Rows_Deleted__c, Rows_Created__c, Rows_Rejected__c, ' +
				'Operation_JSON__c, Run_Log__c',
				BigObjectArchiveJob.OPERATION_ARCHIVE,
				null,
				RUNS_SHOWN,
				false
			)
		) {
			RunView view = new RunView();
			view.id = job.Id;
			view.name = job.Name;
			view.status = job.Status__c;
			view.running = ImportBatchService.STATUS_COMMITTING.equals(job.Status__c);
			view.startedAt = job.Started_At__c;
			view.moved = DataJobs.intOf(job.Rows_Deleted__c);
			view.leftOut = DataJobs.intOf(job.Rows_Rejected__c);
			view.log = job.Run_Log__c;
			try {
				view.ruleName = (String) ((Map<String, Object>) JSON.deserializeUntyped(job.Operation_JSON__c))
					.get('name');
			} catch (Exception notJson) {
				view.ruleName = null;
			}
			result.add(view);
		}
		return result;
	}

	/**
	 * Saves a rule on one of the person's own saved queries, or takes it off (null). Turning a
	 * schedule on needs the count the preview shows now, typed once.
	 */
	public static void save(Id queryId, ArchiveRules.Rule rule, Integer confirmedCount) {
		requireAllowed();
		Saved_Query__c query = readQuery(queryId);
		if (query.OwnerId != UserInfo.getUserId()) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_Find_ErrorNotYours'));
		}
		if (rule != null) {
			ArchiveRules.check(rule);
			String reason = ArchiveDestinations.forKey(rule.destination).unavailableReason();
			if (reason != null) {
				throw new ArchiveRules.ArchiveRuleException(reason);
			}
			BulkDeleteService.Plan checked = BulkDeleteService.plan(query.Query_JSON__c);
			ArchiveRules.Rule before = ArchiveRules.of(query.Query_JSON__c);
			Boolean turningOn = rule.scheduled() && (before == null || !before.scheduled());
			if (turningOn) {
				Integer count = BulkDeleteService.countWithin(checked, BulkDeleteService.runLimit());
				if (confirmedCount == null || confirmedCount != count) {
					throw new ArchiveRules.ArchiveRuleException(
						String.format(
							BarnHelp.text('Core', 'Core_ArchiveRules_ErrorScheduleConfirm'),
							new List<Object>{ count.format() }
						)
					);
				}
			}
		}
		Database.update(
			new Saved_Query__c(Id = query.Id, Query_JSON__c = ArchiveRules.withRule(query.Query_JSON__c, rule)),
			AccessLevel.USER_MODE
		);
	}

	/**
	 * What running the query as a rule now would do: the bulk delete preview (count, sample,
	 * children). Any saved query the person may read, so a schedule can be confirmed before the
	 * query is a rule.
	 */
	public static BulkDeleteService.Preview preview(Id queryId) {
		requireAllowed();
		Saved_Query__c query = readQuery(queryId);
		return BulkDeleteService.preview(query.Query_JSON__c);
	}

	/** Runs a rule now, for at most the count the person typed from the preview. */
	public static Import_Batch__c run(Id queryId, Integer confirmedCount) {
		requireAllowed();
		Saved_Query__c query = readRule(queryId);
		BulkDeleteService.Plan checked = BulkDeleteService.plan(query.Query_JSON__c);
		if (confirmedCount == null || confirmedCount < 1) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_BulkUpdate_ErrorConfirm'));
		}
		Integer count = BulkDeleteService.countWithin(checked, confirmedCount);
		if (count > confirmedCount) {
			throw new ArchiveRules.ArchiveRuleException(
				String.format(
					BarnHelp.text('Core', 'Core_BulkDelete_ErrorMoreThanConfirmed'),
					new List<Object>{ confirmedCount.format() }
				)
			);
		}
		return start(query, checked, confirmedCount, false);
	}

	/** The saved queries whose archive rule is due on `day` and left on. */
	public static Set<Id> dueRuleIds(Date day) {
		Set<Id> due = new Set<Id>();
		// Every saved query is read: a rule's owner set its schedule, and the nightly run is the
		// administrator's own job (ADR-0166). The records are still read and deleted in user mode.
		for (Saved_Query__c query : [
			SELECT Id, Query_JSON__c
			FROM Saved_Query__c
			WITH SYSTEM_MODE
			ORDER BY Name
			LIMIT :QUERIES_READ
		]) {
			if (ArchiveRules.isDue(ArchiveRules.of(query.Query_JSON__c), day)) {
				due.add(query.Id);
			}
		}
		return due;
	}

	/**
	 * Starts one due rule's run for the nightly step, within the run limit. A rule matching nothing
	 * starts nothing; a rule that cannot start is logged. A rule whose owner is inactive or no
	 * longer holds the permissions is skipped, with a Failed run saying why (D-223). Returns
	 * whether a run started.
	 */
	public static Boolean runDueRule(Id queryId) {
		List<Saved_Query__c> found = [
			SELECT Id, Name, OwnerId, Object_Name__c, Query_JSON__c
			FROM Saved_Query__c
			WHERE Id = :queryId
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (found.isEmpty() || !ArchiveRules.isRule(found[0].Query_JSON__c)) {
			return false;
		}
		Saved_Query__c query = found[0];
		String ownerProblem = ownerProblem(query.OwnerId, ArchiveRules.of(query.Query_JSON__c).destination);
		if (ownerProblem != null) {
			skip(query, ownerProblem);
			return false;
		}
		try {
			BulkDeleteService.Plan checked = BulkDeleteService.plan(query.Query_JSON__c);
			Integer ceiling = BulkDeleteService.runLimit();
			Integer count = DataJobs.countWithin(query.Query_JSON__c, ceiling, 100);
			if (count == null || count == 0) {
				return false;
			}
			start(query, checked, Math.min(count, ceiling), true);
			return true;
		} catch (Exception refused) {
			ErrorLogger.log(refused, CONTEXT, query.Id);
			return false;
		}
	}

	/**
	 * Why the owner of a scheduled rule may no longer have it run, or null (D-223): inactive, or
	 * without a permission `allowed` checks when a rule is saved or run by hand, or, for the big
	 * object, without create access to it. Read in system mode: the nightly run is not the owner.
	 * A profile's own permission set is assigned like any other, so one query covers both.
	 */
	@TestVisible
	private static String ownerProblem(Id ownerId, String destination) {
		List<User> owner = [SELECT Name, IsActive FROM User WHERE Id = :ownerId WITH SYSTEM_MODE LIMIT 1];
		if (owner.isEmpty() || !owner[0].IsActive) {
			return BarnHelp.text(
				'Core',
				'Core_ArchiveRules_SkipInactive',
				new List<Object>{ owner.isEmpty() ? String.valueOf(ownerId) : owner[0].Name }
			);
		}
		Set<Id> sets = new Set<Id>();
		for (PermissionSetAssignment one : [
			SELECT PermissionSetId
			FROM PermissionSetAssignment
			WHERE AssigneeId = :ownerId
			WITH SYSTEM_MODE
		]) {
			sets.add(one.PermissionSetId);
		}
		Set<Id> held = new Set<Id>();
		for (SetupEntityAccess one : [
			SELECT SetupEntityId
			FROM SetupEntityAccess
			WHERE ParentId IN :sets AND SetupEntityType = 'CustomPermission'
			WITH SYSTEM_MODE
		]) {
			held.add(one.SetupEntityId);
		}
		List<String> missing = new List<String>();
		// An archive administrator holds Manage BarnCRM Settings or Manage Archive (AR-14).
		List<String> adminLabels = new List<String>();
		Boolean admin = false;
		Set<String> names = new Set<String>(RUN_PERMISSIONS);
		names.add(ARCHIVE_PERMISSION);
		for (CustomPermission one : [
			SELECT Id, DeveloperName, MasterLabel
			FROM CustomPermission
			WHERE DeveloperName IN :names
			WITH SYSTEM_MODE
			ORDER BY MasterLabel
		]) {
			Boolean adminKind = one.DeveloperName == DataJobs.EVERYONE_PERMISSION ||
				one.DeveloperName == ARCHIVE_PERMISSION;
			if (adminKind) {
				adminLabels.add(one.MasterLabel);
				admin = admin || held.contains(one.Id);
			} else if (!held.contains(one.Id)) {
				missing.add(one.MasterLabel);
			}
		}
		if (!admin && !adminLabels.isEmpty()) {
			missing.add(0, String.join(adminLabels, ' or '));
		}
		if (
			destination == ArchiveRules.BIG_OBJECT &&
			[
				SELECT COUNT()
				FROM ObjectPermissions
				WHERE
					ParentId IN :sets
					AND SobjectType = :Schema.SObjectType.Archived_Record__b.getName()
					AND PermissionsCreate = TRUE
				WITH SYSTEM_MODE
			] == 0
		) {
			missing.add(BarnHelp.text('Core', 'Core_ArchiveRules_SkipBigObject'));
		}
		return missing.isEmpty()
			? null
			: BarnHelp.text(
					'Core',
					'Core_ArchiveRules_SkipPermissions',
					new List<Object>{ owner[0].Name, String.join(missing, ', ') }
			  );
	}

	/**
	 * Records a scheduled run skipped for its owner (D-223): a Failed Archive job for the rule,
	 * whose log says why and what to do, so the rule's last run in the panel shows it, and a
	 * Warning on the Error Log naming the rule. The package's own bookkeeping (ADR-0021).
	 */
	private static void skip(Saved_Query__c query, String reason) {
		Datetime now = Datetime.now();
		String line = BarnHelp.text(
			'Core',
			'Core_ArchiveRules_LogSkipped',
			new List<Object>{ query.Name, now.format(), reason }
		);
		Database.insert(
			new Import_Batch__c(
				Operation__c = BigObjectArchiveJob.OPERATION_ARCHIVE,
				Operation_JSON__c = JSON.serialize(
					new Map<String, Object>{
						'version' => 1,
						'action' => 'archive',
						'savedQueryId' => query.Id,
						'name' => query.Name,
						'object' => query.Object_Name__c,
						'scheduled' => true,
						'skipped' => true
					}
				),
				Status__c = ImportBatchService.STATUS_FAILED,
				Is_Dry_Run__c = false,
				Row_Count__c = 0,
				Rows_Created__c = 0,
				Rows_Deleted__c = 0,
				Rows_Rejected__c = 0,
				Started_At__c = now,
				Completed_At__c = now,
				Committed_By__c = UserInfo.getUserId(),
				Run_Log__c = line
			),
			AccessLevel.SYSTEM_MODE
		);
		ErrorLogger.logMessage(line, CONTEXT, ErrorLogger.SEVERITY_WARNING, query.Id);
	}

	private static Import_Batch__c start(
		Saved_Query__c query,
		BulkDeleteService.Plan checked,
		Integer confirmedCount,
		Boolean scheduled
	) {
		BigObjectArchiveJob.requireIdle(query.Id);
		ArchiveRules.Rule rule = ArchiveRules.of(query.Query_JSON__c);
		ArchiveRun run = new ArchiveRun(query.Id, query.Name, query.Query_JSON__c, checked.objectName, confirmedCount);
		run.scheduled = scheduled;
		// A backup first, which starts the run once saved, unless Skip Backup Before Archive (AR-15).
		return ArchiveBackupGate.start(run, rule.destination);
	}

	private static Saved_Query__c readRule(Id queryId) {
		Saved_Query__c query = readQuery(queryId);
		if (!ArchiveRules.isRule(query.Query_JSON__c)) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveRules_ErrorNotRule'));
		}
		return query;
	}

	private static Saved_Query__c readQuery(Id queryId) {
		List<Saved_Query__c> found = [
			SELECT Id, Name, OwnerId, Query_JSON__c
			FROM Saved_Query__c
			WHERE Id = :queryId
			WITH USER_MODE
			LIMIT 1
		];
		if (found.isEmpty()) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_Find_ErrorNotFound'));
		}
		return found[0];
	}

	private static void requireAllowed() {
		if (!allowed()) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveRules_ErrorNoPermission'));
		}
	}
}
