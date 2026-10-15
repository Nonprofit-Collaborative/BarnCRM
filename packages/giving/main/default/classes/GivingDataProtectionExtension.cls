/**
 * The class Core finds by name (in `DataProtectionExtensions.EXTENSION_CLASSES`) to learn which
 * of Giving's objects no import may write, a one-object load included (canonical model R-IT14;
 * ADR-0080 `0080-import-load-one-object.md`). Giving names them so Core stays neutral (ADR-0059).
 *
 * Receipts, their runs and number sequences are an audit trail (ADR-0010, ADR-0024), and the
 * acknowledgment ledger and its runs record what was sent (ADR-0032). They change only through
 * Giving's own pages and jobs.
 *
 * `@NamespaceAccessible`, public and with a public no-argument constructor, because Core
 * resolves it with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class GivingDataProtectionExtension implements DataProtectionExtension {
    @NamespaceAccessible
    public GivingDataProtectionExtension() {
        return;
    }

    public Set<Schema.SObjectType> protectedObjects() {
        return new Set<Schema.SObjectType>{
            Receipt__c.SObjectType,
            Receipt_Run__c.SObjectType,
            Receipt_Number_Sequence__c.SObjectType,
            Acknowledgment__c.SObjectType,
            Acknowledgment_Run__c.SObjectType
        };
    }
}
