/**
 * The two object checks of Org Optimizer's Unused setup section (admin guide org-optimizer.md):
 * objects near their custom field limit, and record types no record uses or that are inactive.
 *
 * Only BarnCRM's own objects plus Account and Contact are looked at, never the whole schema, so
 * the work is bounded: one describe per object (the field map's names, no field describes), one
 * RecordType query, and at most MAX_RECORD_TYPES one-row queries on RecordTypeId, which is
 * indexed. Read only, in user mode. Called from OrgOptimizerSetupController, which checks the
 * Manage BarnCRM Settings permission first.
 */
public with sharing class OrgOptimizerObjectChecks {
    /** An object at this share of its limit or more is listed. */
    @TestVisible
    private static final Decimal NEAR_SHARE = 0.8;
    /** The most active record types read for a first record. */
    @TestVisible
    private static final Integer MAX_RECORD_TYPES = 50;
    private static final Integer DEFAULT_FIELD_LIMIT = 500;
    /** Custom fields allowed per object by edition, as Organization.OrganizationType names it. */
    private static final Map<String, Integer> FIELD_LIMIT_BY_EDITION = new Map<String, Integer>{
        'Professional Edition' => 100,
        'Enterprise Edition' => 500,
        'Developer Edition' => 500,
        'Unlimited Edition' => 800,
        'Performance Edition' => 800
    };

    /** The objects looked at: Core's own, plus the two standard objects Core extends. */
    private static final List<SObjectType> OBJECTS = new List<SObjectType>{
        Account.SObjectType,
        Contact.SObjectType,
        Address__c.SObjectType,
        Affiliation__c.SObjectType,
        Household_Member__c.SObjectType,
        Relationship__c.SObjectType,
        Import_Batch__c.SObjectType,
        Import_Row__c.SObjectType,
        Import_Journal__c.SObjectType,
        Import_Template__c.SObjectType,
        Error_Log__c.SObjectType,
        Saved_Query__c.SObjectType,
        Rollup_Definition__c.SObjectType
    };

    /** Stands in for the edition's limit in tests. */
    @TestVisible
    private static Integer fieldLimitOverride;

    /**
     * Objects with at least NEAR_SHARE of their custom field limit used. A field from an
     * installed package (a namespace prefix in its name) does not count against the limit and
     * is left out.
     */
    public static OrgOptimizerSetupController.Finding nearFieldLimit() {
        OrgOptimizerSetupController.Finding finding = new OrgOptimizerSetupController.Finding();
        finding.key = 'objectsNearFieldLimit';
        finding.setupUrl = '/lightning/setup/ObjectManager/home';
        try {
            Integer fieldLimit = fieldLimit();
            finding.count = 0;
            for (SObjectType type : OBJECTS) {
                DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
                Integer custom = 0;
                for (String name : describe.fields.getMap().keySet()) {
                    // A local custom field has one double underscore (before the suffix); a
                    // packaged one has a second, after its namespace prefix.
                    if (name.endsWith('__c') && name.countMatches('__') == 1) {
                        custom++;
                    }
                }
                if (custom >= fieldLimit * NEAR_SHARE) {
                    finding.count++;
                }
                if (custom >= fieldLimit * NEAR_SHARE && finding.examples.size() < 5) {
                    finding.examples.add(
                        String.format(
                            Label.Core_OrgOptimizer_FieldLimitExample,
                            new List<Object>{ describe.getLabel(), custom, fieldLimit }
                        )
                    );
                }
            }
        } catch (Exception caught) {
            fail(finding);
        }
        return finding;
    }

    /** Inactive record types, and active ones no record uses, on the objects looked at. */
    public static OrgOptimizerSetupController.Finding unusedRecordTypes() {
        OrgOptimizerSetupController.Finding finding = new OrgOptimizerSetupController.Finding();
        finding.key = 'unusedRecordTypes';
        finding.setupUrl = '/lightning/setup/ObjectManager/home';
        try {
            Set<String> objectNames = new Set<String>();
            for (SObjectType type : OBJECTS) {
                objectNames.add(type.getDescribe(SObjectDescribeOptions.DEFERRED).getName());
            }
            List<RecordType> recordTypes = Database.queryWithBinds(
                'SELECT Id, Name, SobjectType, IsActive FROM RecordType' +
                ' WHERE SobjectType IN :objectNames ORDER BY SobjectType, Name',
                new Map<String, Object>{ 'objectNames' => objectNames },
                AccessLevel.USER_MODE
            );
            List<String> found = new List<String>();
            Integer read = 0;
            for (RecordType recordType : recordTypes) {
                if (!recordType.IsActive) {
                    found.add(
                        String.format(
                            Label.Core_OrgOptimizer_RecordTypeInactive,
                            new List<Object>{ recordType.SobjectType, recordType.Name }
                        )
                    );
                } else if (read < MAX_RECORD_TYPES) {
                    read++;
                    if (!isUsed(recordType)) {
                        found.add(
                            String.format(
                                Label.Core_OrgOptimizer_RecordTypeUnused,
                                new List<Object>{ recordType.SobjectType, recordType.Name }
                            )
                        );
                    }
                }
            }
            finding.count = found.size();
            for (Integer index = 0; index < Math.min(found.size(), 5); index++) {
                finding.examples.add(found[index]);
            }
        } catch (Exception caught) {
            fail(finding);
        }
        return finding;
    }

    /** Whether at least one record the person can see has this record type. */
    private static Boolean isUsed(RecordType recordType) {
        List<SObject> one = Database.queryWithBinds(
            'SELECT Id FROM ' +
                String.escapeSingleQuotes(recordType.SobjectType) +
                ' WHERE RecordTypeId = :recordTypeId LIMIT 1',
            new Map<String, Object>{ 'recordTypeId' => recordType.Id },
            AccessLevel.USER_MODE
        );
        return !one.isEmpty();
    }

    private static Integer fieldLimit() {
        if (fieldLimitOverride != null) {
            return fieldLimitOverride;
        }
        List<Organization> org = Database.query(
            'SELECT OrganizationType FROM Organization LIMIT 1',
            AccessLevel.USER_MODE
        );
        Integer known = org.isEmpty() ? null : FIELD_LIMIT_BY_EDITION.get(org[0].OrganizationType);
        return known == null ? DEFAULT_FIELD_LIMIT : known;
    }

    private static void fail(OrgOptimizerSetupController.Finding finding) {
        finding.failed = true;
        finding.count = null;
        finding.examples.clear();
    }
}
