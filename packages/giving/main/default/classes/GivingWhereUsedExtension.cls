/**
 * Giving's part of Where Used (C-59, ADR-0159 `0159-where-used-extension.md`): the import mapping
 * columns and default values that load gifts, allocations, soft credits and tributes. Core reads
 * a mapping's people, household and organization columns itself; only Giving knows which object
 * each of its row entities loads (R-IR1, R-IR6), so it passes them to Core's reader. Core finds
 * this class by name (`WhereUsedExtensions`).
 *
 * Donor segments are saved Find queries (R-DS1), so Core's saved query list already covers them.
 */
@NamespaceAccessible
public with sharing class GivingWhereUsedExtension implements WhereUsedExtension {
    /** Giving's row entities by the object each one loads. */
    @TestVisible
    private static final Map<String, String> ENTITY_OBJECTS = new Map<String, String>{
        'Gift' => 'Gift__c',
        'Allocation' => 'Gift_Allocation__c',
        'SoftCredit' => 'Soft_Credit__c',
        'Tribute' => 'Tribute__c'
    };

    @NamespaceAccessible
    public GivingWhereUsedExtension() {
        // Built by name from Core (WhereUsedExtensions), so it needs a public constructor.
    }

    public List<WhereUsedService.Reference> references(WhereUsedService.Target target) {
        List<WhereUsedService.Reference> found = WhereUsedService.importColumnReferences(
            target,
            ENTITY_OBJECTS
        );
        found.addAll(settingReferences(target));
        return found;
    }

    /**
     * Giving settings whose value names a field: the Donor Level source total (R-DL7), read on
     * both Account and Contact. Its effective value counts, because that is what levels run on.
     */
    @TestVisible
    private static List<WhereUsedService.Reference> settingReferences(
        WhereUsedService.Target target
    ) {
        List<WhereUsedService.Reference> found = new List<WhereUsedService.Reference>();
        String source = DonorLevelService.sourceField();
        if (
            !target.isObject() &&
            (target.matchesField('Contact', source) || target.matchesField('Account', source))
        ) {
            found.add(
                WhereUsedService.settingReference(
                    Schema.Giving_Settings__c.Donor_Level_Source_Field__c.getDescribe().getLabel(),
                    System.Label.Core_WhereUsed_BreaksSettingValue,
                    'Giving'
                )
            );
        }
        return found;
    }
}
