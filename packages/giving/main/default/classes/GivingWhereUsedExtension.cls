/**
 * Giving's part of Where Used (C-59, ADR-NEXT `NEXT-where-used-extension.md`): the import mapping
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
        return WhereUsedService.importColumnReferences(target, ENTITY_OBJECTS);
    }
}
