/**
 * Brand-restricted visibility upkeep (C-47c, canonical model R-BR7, ADR-0202 brand management
 * and visibility, decisions 4 to 6).
 *
 * Two phases, because groups and group members are setup objects and Account shares are not,
 * and one transaction cannot write both (the mixed DML rule):
 *
 * 1. Groups: one public group per active brand while visibility is on, named
 *    `BarnCRM_Brand_` plus the brand ID, whose members are the users assigned to the brand. A
 *    group no longer wanted is deleted, and Salesforce deletes the shares granted to it with it,
 *    which is how turning visibility off removes every row BarnCRM added.
 * 2. Shares: for each Account in scope, a Manual Edit share to each of its brands' groups, and
 *    only BarnCRM's own rows removed. Scope is the Accounts a Brand Assignment change touched, or
 *    every assigned Account in pages after a Brand or setting change.
 *
 * Queries run in system mode: the job works for the whole org, not for what the person who
 * saved can see. Writes go through `BrandShareWriter`.
 */
public with sharing class BrandShareJob implements Queueable {
	public static final String GROUP_PREFIX = 'BarnCRM_Brand_';
	private static final Integer PAGE = 500;
	private static Boolean fullRequested = false;
	private static Set<Id> pendingAccounts;

	private final Boolean sharesPhase;
	private final Boolean full;
	private final Set<Id> accountIds;
	private final Id cursor;

	@TestVisible
	private BrandShareJob(Boolean sharesPhase, Boolean full, Set<Id> accountIds, Id cursor) {
		this.sharesPhase = sharesPhase;
		this.full = full;
		this.accountIds = accountIds == null ? new Set<Id>() : accountIds;
		this.cursor = cursor;
	}

	/** After a Brand or a setting change: groups, then every assigned Account. Once per transaction. */
	public static void requestFull() {
		if (!fullRequested && enqueue(new BrandShareJob(false, true, null, null))) {
			fullRequested = true;
		}
	}

	/** After a Brand Assignment change: groups, then the Accounts it touched. */
	public static void request(List<SObject> assignments) {
		if (!BrandService.visibilityOn() || fullRequested) {
			return;
		}
		Set<Id> contactIds = new Set<Id>();
		Set<Id> touched = new Set<Id>();
		for (SObject row : assignments) {
			Brand_Assignment__c assignment = (Brand_Assignment__c) row;
			if (assignment.Account__c != null) {
				touched.add(assignment.Account__c);
			}
			if (assignment.Contact__c != null) {
				contactIds.add(assignment.Contact__c);
			}
		}
		for (Contact person : [
			SELECT AccountId
			FROM Contact
			WHERE Id IN :contactIds AND AccountId != NULL
			WITH SYSTEM_MODE
		]) {
			touched.add(person.AccountId);
		}
		if (pendingAccounts == null) {
			pendingAccounts = touched;
			enqueue(new BrandShareJob(false, false, pendingAccounts, null));
		} else {
			// Already queued in this transaction: the job reads the same set when it runs.
			pendingAccounts.addAll(touched);
		}
	}

	private static Boolean enqueue(BrandShareJob job) {
		if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
			ErrorLogger.logMessage(
				BarnHelp.text('Core', 'Core_Brand_ShareNotQueued'),
				'BrandShareJob.enqueue',
				ErrorLogger.SEVERITY_WARNING
			);
			return false;
		}
		System.enqueueJob(job);
		return true;
	}

	public void execute(QueueableContext context) {
		try {
			if (!sharesPhase) {
				Map<Id, Id> groups = syncGroups();
				if (BrandService.visibilityOn() && !groups.isEmpty()) {
					System.enqueueJob(new BrandShareJob(true, full, accountIds, null));
				}
				return;
			}
			Set<Id> scope = accountIds;
			Id last;
			if (full) {
				scope = new Set<Id>();
				// "Id > null" matches no rows, so the first page starts from the lowest possible Id.
				Id floor = cursor != null
					? cursor
					: Id.valueOf(
							Brand_Assignment__c.SObjectType.getDescribe(
									SObjectDescribeOptions.DEFERRED
								)
								.getKeyPrefix() + '000000000000'
					  );
				for (Brand_Assignment__c row : [
					SELECT Id, Account__c, Contact__r.AccountId
					FROM Brand_Assignment__c
					WHERE Id > :floor AND (Account__c != NULL OR Contact__c != NULL)
					WITH SYSTEM_MODE
					ORDER BY Id
					LIMIT :PAGE
				]) {
					scope.add(row.Account__c != null ? row.Account__c : row.Contact__r.AccountId);
					last = row.Id;
				}
				scope.remove(null);
			}
			syncShares(scope, groupsByBrand());
			if (full && last != null) {
				System.enqueueJob(new BrandShareJob(true, true, null, last));
			}
		} catch (Exception failure) {
			ErrorLogger.log(failure, 'BrandShareJob.execute');
		}
	}

	/** Phase 1. Returns the groups kept, by brand ID. */
	@TestVisible
	private static Map<Id, Id> syncGroups() {
		Set<Id> wanted = new Set<Id>();
		Map<Id, Set<Id>> members = new Map<Id, Set<Id>>();
		if (BrandService.visibilityOn()) {
			for (Brand__c brand : [
				SELECT Id
				FROM Brand__c
				WHERE Active__c = TRUE
				WITH SYSTEM_MODE
			]) {
				wanted.add(brand.Id);
				members.put(brand.Id, new Set<Id>());
			}
			for (Brand_Assignment__c row : [
				SELECT Brand__c, User__c
				FROM Brand_Assignment__c
				WHERE User__c != NULL AND Brand__c IN :wanted
				WITH SYSTEM_MODE
			]) {
				members.get(row.Brand__c).add(row.User__c);
			}
		}
		Map<Id, Id> groups = groupsByBrand();
		List<Group> stale = new List<Group>();
		for (Id brandId : new List<Id>(groups.keySet())) {
			if (!wanted.contains(brandId)) {
				stale.add(new Group(Id = groups.remove(brandId)));
			}
		}
		BrandShareWriter.deleteRows(stale);
		List<Group> created = new List<Group>();
		for (Id brandId : wanted) {
			if (!groups.containsKey(brandId)) {
				created.add(
					new Group(
						Name = 'BarnCRM Brand ' + String.valueOf(brandId).left(15),
						DeveloperName = GROUP_PREFIX + brandId,
						Type = 'Regular'
					)
				);
			}
		}
		BrandShareWriter.insertRows(created);
		groups = groupsByBrand();

		Map<String, GroupMember> existing = new Map<String, GroupMember>();
		for (GroupMember member : [
			SELECT Id, GroupId, UserOrGroupId
			FROM GroupMember
			WHERE GroupId IN :groups.values()
			WITH SYSTEM_MODE
		]) {
			existing.put('' + member.GroupId + member.UserOrGroupId, member);
		}
		List<GroupMember> added = new List<GroupMember>();
		for (Id brandId : groups.keySet()) {
			for (Id userId : members.get(brandId)) {
				String key = '' + groups.get(brandId) + userId;
				if (existing.remove(key) == null) {
					added.add(
						new GroupMember(GroupId = groups.get(brandId), UserOrGroupId = userId)
					);
				}
			}
		}
		BrandShareWriter.insertRows(added);
		BrandShareWriter.deleteRows(existing.values());
		return groups;
	}

	/** Phase 2: the wanted shares of these Accounts, BarnCRM's own rows only. */
	@TestVisible
	private static void syncShares(Set<Id> accountIds, Map<Id, Id> groups) {
		if (accountIds == null || accountIds.isEmpty()) {
			return;
		}
		Set<String> wanted = new Set<String>();
		for (Brand_Assignment__c row : [
			SELECT Brand__c, Account__c, Contact__r.AccountId
			FROM Brand_Assignment__c
			WHERE Account__c IN :accountIds OR Contact__r.AccountId IN :accountIds
			WITH SYSTEM_MODE
		]) {
			Id groupId = groups.get(row.Brand__c);
			Id accountId = row.Account__c != null ? row.Account__c : row.Contact__r.AccountId;
			if (groupId != null && accountIds.contains(accountId)) {
				wanted.add('' + accountId + groupId);
			}
		}
		List<AccountShare> extra = new List<AccountShare>();
		for (AccountShare share : [
			SELECT Id, AccountId, UserOrGroupId
			FROM AccountShare
			WHERE
				AccountId IN :accountIds
				AND UserOrGroupId IN :groups.values()
				AND RowCause = 'Manual'
			WITH SYSTEM_MODE
		]) {
			if (!wanted.remove('' + share.AccountId + share.UserOrGroupId)) {
				extra.add(share);
			}
		}
		BrandShareWriter.deleteRows(extra);
		Map<String, Schema.SObjectField> fields = Schema.SObjectType.AccountShare.fields.getMap();
		List<AccountShare> added = new List<AccountShare>();
		for (String key : wanted) {
			AccountShare share = new AccountShare(
				AccountId = (Id) key.left(18),
				UserOrGroupId = (Id) key.right(18),
				AccountAccessLevel = 'Edit'
			);
			// Which access levels an org asks for depends on its objects and its Contact
			// sharing; each is set only when the org lets it be written.
			for (String level : new List<String>{ 'OpportunityAccessLevel', 'CaseAccessLevel' }) {
				if (fields.containsKey(level) && fields.get(level).getDescribe().isCreateable()) {
					share.put(level, 'None');
				}
			}
			if (
				fields.containsKey('ContactAccessLevel') &&
				fields.get('ContactAccessLevel').getDescribe().isCreateable()
			) {
				share.put('ContactAccessLevel', 'Edit');
			}
			added.add(share);
		}
		BrandShareWriter.insertRows(added);
	}

	@TestVisible
	private static Map<Id, Id> groupsByBrand() {
		Map<Id, Id> groups = new Map<Id, Id>();
		String prefix = GROUP_PREFIX + '%';
		for (Group brandGroup : [
			SELECT Id, DeveloperName
			FROM Group
			WHERE DeveloperName LIKE :prefix AND Type = 'Regular'
			WITH SYSTEM_MODE
		]) {
			try {
				groups.put(
					Id.valueOf(brandGroup.DeveloperName.removeStart(GROUP_PREFIX)),
					brandGroup.Id
				);
			} catch (StringException notOurs) {
				continue;
			}
		}
		return groups;
	}

	/** Health Check (ADR-0202 decision 5): visibility restricts nothing until Accounts are Private. */
	public with sharing class VisibilityCheck implements HealthCheckService.Check {
		public HealthCheckService.Finding run() {
			if (!BrandService.visibilityOn()) {
				return null;
			}
			List<Organization> org = [
				SELECT DefaultAccountAccess
				FROM Organization
				WITH SYSTEM_MODE
				LIMIT 1
			];
			if (org.isEmpty() || org[0].DefaultAccountAccess == 'None') {
				return null;
			}
			return new HealthCheckService.Finding(
				'brand_visibility',
				BarnHelp.text('Core', 'Core_Brand_VisibilityTitle'),
				BarnHelp.text('Core', 'Core_Brand_VisibilityDetail'),
				HealthCheckService.SEVERITY_WARNING,
				HealthCheckService.CATEGORY_SETTINGS
			);
		}
	}
}
