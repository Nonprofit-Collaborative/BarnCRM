/**
 * Brings `Account.Is_Organization_Account__c` in line with Record type for organizations on every
 * account whose flag disagrees (canonical model R-O4; ADR-0238 settings as custom metadata,
 * decision 8). The account trigger sets the flag on each save; this runs when the setting
 * changes and on each install, since a custom metadata value cannot drive a formula field.
 *
 * Only accounts whose flag is wrong are read, so a run after a save that changed nothing
 * touches nothing. `without sharing` (register: Org job): an account the person who saved the
 * setting cannot see must still be counted right in the Organizations list view.
 */
public without sharing class OrganizationFlagBatch implements Database.Batchable<SObject> {
	/** Each account save runs every Account trigger handler, so chunks stay at the usual 200. */
	private static final Integer CHUNK_SIZE = 200;
	private static final String CONTEXT = 'OrganizationFlagBatch';

	/**
	 * Lets a test start the run. Off by default, so a test of a settings save or an install does
	 * not leave a batch that runs at `Test.stopTest` beside the batch it is about.
	 */
	@TestVisible
	private static Boolean runInTests = false;

	/** Starts the run, or refuses when the org is busy (AsyncStarter); the next save retries. */
	public static Id run() {
		if (Test.isRunningTest() && !runInTests) {
			return null;
		}
		return AsyncStarter.batch(new OrganizationFlagBatch(), CHUNK_SIZE, CONTEXT);
	}

	/** The flag an account of this record type should carry. */
	public static void stamp(List<Account> accounts) {
		for (Account record : accounts) {
			Boolean flag = AccountKinds.isOrganization(record.RecordTypeId);
			if (record.Is_Organization_Account__c != flag) {
				record.Is_Organization_Account__c = flag;
			}
		}
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		Set<Id> organizationTypes = new Set<Id>();
		Boolean noRecordType = AccountKinds.NO_RECORD_TYPE.equalsIgnoreCase(AccountKinds.organizationRecordTypeName());
		if (noRecordType) {
			for (Schema.RecordTypeInfo info : Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
				.getRecordTypeInfos()) {
				if (info.isMaster()) {
					organizationTypes.add(info.getRecordTypeId());
				}
			}
		} else if (AccountKinds.organizationRecordTypeId() != null) {
			organizationTypes.add(AccountKinds.organizationRecordTypeId());
		}
		String isOrganization = noRecordType
			? '(RecordTypeId = NULL OR RecordTypeId IN :organizationTypes)'
			: 'RecordTypeId IN :organizationTypes';
		String isNot = noRecordType
			? '(RecordTypeId != NULL AND RecordTypeId NOT IN :organizationTypes)'
			: '(RecordTypeId = NULL OR RecordTypeId NOT IN :organizationTypes)';
		return Database.getQueryLocator(
			'SELECT Id, RecordTypeId, Is_Organization_Account__c FROM Account WHERE (' +
				isOrganization +
				' AND Is_Organization_Account__c = FALSE) OR (' +
				isNot +
				' AND Is_Organization_Account__c = TRUE)',
			AccessLevel.SYSTEM_MODE
		);
	}

	public void execute(Database.BatchableContext batchContext, List<Account> scope) {
		List<Account> changed = new List<Account>();
		List<Id> ids = new List<Id>();
		for (Account record : scope) {
			changed.add(
				new Account(Id = record.Id, Is_Organization_Account__c = AccountKinds.isOrganization(record.RecordTypeId))
			);
			ids.add(record.Id);
		}
		ErrorLogger.logFailures(
			Database.update(changed, false, AccessLevel.SYSTEM_MODE),
			ids,
			CONTEXT,
			ErrorLogger.SEVERITY_WARNING
		);
	}

	public void finish(Database.BatchableContext context) {
		// Nothing to report: an account that failed is logged, and its next save sets its flag.
	}
}
