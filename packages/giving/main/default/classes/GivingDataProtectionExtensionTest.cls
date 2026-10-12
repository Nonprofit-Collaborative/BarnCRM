/**
 * Giving's receipts and acknowledgment ledger are refused by a one-object load through Core's
 * extension seam, and its everyday records are not (canonical model R-IT14).
 */
@IsTest
private class GivingDataProtectionExtensionTest {
    @IsTest
    static void receiptsAndTheAcknowledgmentLedgerAreProtected() {
        Set<Schema.SObjectType> objects = new GivingDataProtectionExtension().protectedObjects();
        Assert.isTrue(objects.contains(Receipt__c.SObjectType), 'Receipts.');
        Assert.isTrue(objects.contains(Receipt_Run__c.SObjectType), 'Receipt runs.');
        Assert.isTrue(
            objects.contains(Receipt_Number_Sequence__c.SObjectType),
            'Receipt number sequences.'
        );
        Assert.isTrue(objects.contains(Acknowledgment__c.SObjectType), 'Acknowledgments.');
        Assert.isTrue(objects.contains(Acknowledgment_Run__c.SObjectType), 'Their runs.');
    }

    @IsTest
    static void coreFindsItAndRefusesThoseObjects() {
        Assert.isTrue(
            DataProtectionExtensions.protectedObjects().contains(Receipt__c.SObjectType),
            'Core resolves Giving by name.'
        );
        Assert.isNotNull(
            DataProtectedFields.objectRefusal(Receipt__c.SObjectType),
            'A receipt is never loaded.'
        );
        Assert.isNotNull(
            DataProtectedFields.objectRefusal(Acknowledgment__c.SObjectType),
            'Nor an acknowledgment.'
        );
        Assert.isNull(
            DataProtectedFields.objectRefusal(Fund__c.SObjectType),
            'A fund is an everyday record.'
        );
    }
}
