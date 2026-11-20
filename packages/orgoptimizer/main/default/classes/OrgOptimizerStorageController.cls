/**
 * Org Optimizer's Storage and limits section (ADR-0103 org-optimizer-and-data-manager-pages,
 * admin guide org-optimizer.md): how much of the org's data and file storage and daily limits
 * are used, read by Core's `OrgLimitReader` (as the weekly admin digest reads them), and how many
 * records BarnCRM's own bookkeeping objects hold, which is what BarnCRM itself adds to data
 * storage.
 *
 * Read only. Requires Manage BarnCRM Settings. Record counts are read in user mode and stop at
 * a cap, because a COUNT() query spends one query row per record it counts.
 */
public with sharing class OrgOptimizerStorageController {
	private static final String PERMISSION = 'Manage_BarnCRM_Settings';
	/** The most records counted per object; above it the page says "more than". */
	@TestVisible
	private static final Integer COUNT_CAP = 10000;
	/** Salesforce counts most records as 2 KB of data storage. */
	private static final Decimal KB_PER_RECORD = 2;
	/** BarnCRM's own objects that grow with use. */
	private static final List<SObjectType> OWN_OBJECTS = new List<SObjectType>{
		Import_Batch__c.SObjectType,
		Import_Row__c.SObjectType,
		Import_Journal__c.SObjectType,
		Error_Log__c.SObjectType,
		Field_Utilization_Snapshot__c.SObjectType,
		Setup_Change__c.SObjectType
	};

	@TestVisible
	private static Boolean permissionOverride;
	/** One of BarnCRM's own objects and what it adds to data storage. */
	public class OwnObject {
		@AuraEnabled
		public String apiName;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public Integer records;
		/** True when the count stopped at the cap. */
		@AuraEnabled
		public Boolean moreThan;
		@AuraEnabled
		public Decimal estimatedMB;
	}

	public class Storage {
		@AuraEnabled
		public List<OrgLimitReader.LimitUse> limits = OrgLimitReader.all();
		@AuraEnabled
		public List<OwnObject> ownObjects = new List<OwnObject>();
		@AuraEnabled
		public Integer countCap = COUNT_CAP;
		/** Whether the person may archive old records to free storage (R-BD9). */
		@AuraEnabled
		public Boolean canArchive = BulkDeleteController.hasPermission();
	}

	@AuraEnabled
	public static Storage getStorage() {
		if (!hasPermission()) {
			throw UserErrors.message(BarnHelp.text('Core', 'Core_OrgOptimizer_ErrorNoPermission'));
		}
		try {
			Storage result = new Storage();
			for (SObjectType type : OWN_OBJECTS) {
				DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
				if (!describe.isAccessible()) {
					continue;
				}
				Integer counted = countUpTo(describe.getName());
				OwnObject own = new OwnObject();
				own.apiName = describe.getName();
				own.label = describe.getLabelPlural();
				own.moreThan = counted > COUNT_CAP;
				own.records = Math.min(counted, COUNT_CAP);
				own.estimatedMB = (own.records * KB_PER_RECORD / 1024).setScale(1);
				result.ownObjects.add(own);
			}
			return result;
		} catch (Exception caught) {
			throw UserErrors.wrap(caught, 'OrgOptimizerStorageController.getStorage', true);
		}
	}

	/** Counts at most COUNT_CAP + 1 records, as the person. */
	private static Integer countUpTo(String objectName) {
		Integer readUpTo = COUNT_CAP + 1;
		return Database.countQueryWithBinds(
			'SELECT COUNT() FROM ' + objectName + ' LIMIT :readUpTo',
			new Map<String, Object>{ 'readUpTo' => readUpTo },
			AccessLevel.USER_MODE
		);
	}

	private static Boolean hasPermission() {
		if (permissionOverride != null) {
			return permissionOverride;
		}
		return FeatureManagement.checkPermission(PERMISSION);
	}
}
