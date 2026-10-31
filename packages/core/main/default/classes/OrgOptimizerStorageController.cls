/**
 * Org Optimizer's Storage and limits section (ADR-0103 org-optimizer-and-data-manager-pages,
 * admin guide org-optimizer.md): how much of the org's data and file storage and daily limits
 * are used, read from `OrgLimits` (no callout, no Tooling API), and how many records BarnCRM's
 * own bookkeeping objects hold, which is what BarnCRM itself adds to data storage.
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
    /** The limits shown, by their OrgLimits name. */
    private static final List<String> LIMIT_NAMES = new List<String>{
        'DataStorageMB',
        'FileStorageMB',
        'DailyApiRequests',
        'DailyAsyncApexExecutions',
        'SingleEmail'
    };
    /** BarnCRM's own objects that grow with use. */
    private static final List<SObjectType> OWN_OBJECTS = new List<SObjectType>{
        Import_Batch__c.SObjectType,
        Import_Row__c.SObjectType,
        Import_Journal__c.SObjectType,
        Error_Log__c.SObjectType,
        Field_Utilization_Snapshot__c.SObjectType
    };

    @TestVisible
    private static Boolean permissionOverride;
    /** Stands in for OrgLimits in tests, by limit name: { used, max }. */
    @TestVisible
    private static Map<String, List<Integer>> limitsOverride;

    /** One org limit. */
    public class LimitUse {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer used;
        @AuraEnabled
        public Integer max;
        @AuraEnabled
        public Integer percent;
    }

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
        public List<LimitUse> limits = new List<LimitUse>();
        @AuraEnabled
        public List<OwnObject> ownObjects = new List<OwnObject>();
        @AuraEnabled
        public Integer countCap = COUNT_CAP;
    }

    @AuraEnabled
    public static Storage getStorage() {
        if (!hasPermission()) {
            throw asAuraError(Label.Core_OrgOptimizer_ErrorNoPermission);
        }
        try {
            Storage result = new Storage();
            Map<String, List<Integer>> readings = readLimits();
            for (String name : LIMIT_NAMES) {
                List<Integer> reading = readings.get(name);
                if (reading == null) {
                    continue;
                }
                result.limits.add(limitUse(name, reading));
            }
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

    /**
     * The limits at or above `threshold` percent, for the weekly admin digest (C-54). No
     * permission check: the caller is the digest, which runs as an administrator.
     */
    public static List<LimitUse> limitsAtOrAbove(Integer threshold) {
        List<LimitUse> found = new List<LimitUse>();
        Map<String, List<Integer>> readings = readLimits();
        for (String name : LIMIT_NAMES) {
            if (readings.get(name) == null) {
                continue;
            }
            LimitUse use = limitUse(name, readings.get(name));
            if (use.percent >= threshold) {
                found.add(use);
            }
        }
        return found;
    }

    private static LimitUse limitUse(String name, List<Integer> reading) {
        LimitUse use = new LimitUse();
        use.name = name;
        use.used = reading[0];
        use.max = reading[1];
        use.percent = use.max == null ||
            use.max <= 0
            ? 0
            : (Integer) Math.min(100, Math.round(100.0 * use.used / use.max));
        return use;
    }

    private static Map<String, List<Integer>> readLimits() {
        if (limitsOverride != null) {
            return limitsOverride;
        }
        Map<String, List<Integer>> result = new Map<String, List<Integer>>();
        Map<String, System.OrgLimit> all = OrgLimits.getMap();
        for (String name : LIMIT_NAMES) {
            System.OrgLimit orgLimit = all.get(name);
            if (orgLimit != null) {
                result.put(name, new List<Integer>{ orgLimit.getValue(), orgLimit.getLimit() });
            }
        }
        return result;
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

    private static AuraHandledException asAuraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
