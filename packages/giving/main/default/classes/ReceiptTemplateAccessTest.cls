/**
 * Where the shipped letters come from, and who may change one (ADR-0034).
 *
 * Two defects sit behind this class. The Receipts page used to materialize the shipped letters
 * from `getTemplates`, which is `@AuraEnabled(cacheable=true)`, and **Apex cannot perform DML in a
 * cacheable method**: on an org that had never issued a receipt, the first screen an administrator
 * opened threw. And the letters were written with no permission check at all, on the object whose
 * body is the letter a donor's accountant reads.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class ReceiptTemplateAccessTest {
    @IsTest
    static void theReceiptsPageReadsTheLettersAndWritesNothing() {
        // No setUpReceipting here on purpose: this is the org that has never issued a receipt,
        // which is the org the page used to throw on.
        Integer dmlBefore = Limits.getDmlStatements();

        Test.startTest();
        List<ReceiptController.TemplateView> views = ReceiptController.getTemplates();
        Test.stopTest();

        Assert.areEqual(
            dmlBefore,
            Limits.getDmlStatements(),
            'A cacheable method performs no DML, which is the platform rule this broke.'
        );
        Assert.isTrue(views.isEmpty(), 'It reports what is there, which on this org is nothing.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Receipt_Template__c],
            'And it created nothing as a side effect of somebody reading a page.'
        );
    }

    @IsTest
    static void restoringTheShippedLettersFillsAnEmptyOrgAndIsSafeTwice() {
        ReceiptTemplateService.managePermission = true;

        Test.startTest();
        List<ReceiptController.TemplateView> restored = ReceiptController.restoreDefaultTemplates();
        List<ReceiptController.TemplateView> again = ReceiptController.restoreDefaultTemplates();
        Test.stopTest();

        Assert.areEqual(
            2,
            restored.size(),
            'The org gets the two letters BarnCRM ships, per gift and consolidated statement.'
        );
        Assert.areEqual(
            restored.size(),
            again.size(),
            'Pressing the button twice leaves the same letters, not four of them.'
        );
        Set<String> types = new Set<String>();
        for (ReceiptController.TemplateView view : again) {
            types.add(view.type);
            Assert.isFalse(
                String.isBlank(view.body),
                'A restored letter carries the shipped wording, not an empty body: ' + view.name
            );
        }
        Assert.areEqual(
            new Set<String>{
                ReceiptNumberSequence.TYPE_PER_GIFT,
                ReceiptNumberSequence.TYPE_STATEMENT
            },
            types,
            'One letter of each kind, which is what the two tabs on the page expect.'
        );
    }

    @IsTest
    static void restoringTheShippedLettersWithoutPermissionIsRefusedAndWritesNothing() {
        ReceiptTemplateService.managePermission = false;

        Test.startTest();
        try {
            ReceiptTemplateService.restoreDefaults();
            Assert.fail('A user without Manage Nonprofit Settings created the shipped letters.');
        } catch (ReceiptTemplateService.ReceiptTemplateException refused) {
            Assert.areEqual(
                Label.Giving_Receipt_NoTemplatePermission,
                refused.getMessage(),
                'It names the role to ask for.'
            );
        }
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Receipt_Template__c],
            'Nothing was written by the refused call.'
        );
    }

    @IsTest
    static void editingALetterWithoutPermissionIsRefusedAndTheLetterIsUnchanged() {
        ReceiptTestDataFactory.setUpReceipting();
        Receipt_Template__c letter = ReceiptSelector.allTemplates()[0];
        String wording = letter.Body__c;
        ReceiptTemplateService.managePermission = false;

        Test.startTest();
        try {
            ReceiptTemplateService.saveBody(letter.Id, '<p>Send us more money.</p>');
            Assert.fail('A user without Manage Nonprofit Settings rewrote a receipt letter.');
        } catch (ReceiptTemplateService.ReceiptTemplateException refused) {
            Assert.areEqual(
                Label.Giving_Receipt_NoTemplatePermission,
                refused.getMessage(),
                'It names the role to ask for.'
            );
        }
        Test.stopTest();

        Assert.areEqual(
            wording,
            [SELECT Body__c FROM Receipt_Template__c WHERE Id = :letter.Id].Body__c,
            'The letter a donor receives is exactly what it was before the refused save.'
        );
    }

    @IsTest
    static void switchingALetterOnWithoutPermissionIsRefusedAndNothingChanges() {
        ReceiptTestDataFactory.setUpReceipting();
        Receipt_Template__c second = new Receipt_Template__c(
            Name = 'Per gift receipt, shorter',
            Type__c = ReceiptNumberSequence.TYPE_PER_GIFT,
            Active__c = false,
            Body__c = '<p>{{OrganizationName}} thanks you for {{Amount}}.</p>'
        );
        insert second;
        ReceiptTemplateService.managePermission = false;

        Test.startTest();
        try {
            ReceiptTemplateService.activate(second.Id);
            Assert.fail('A user without Manage Nonprofit Settings changed the letter in use.');
        } catch (ReceiptTemplateService.ReceiptTemplateException refused) {
            Assert.areEqual(
                Label.Giving_Receipt_NoTemplatePermission,
                refused.getMessage(),
                'It names the role to ask for.'
            );
        }
        Test.stopTest();

        Assert.isFalse(
            [SELECT Active__c FROM Receipt_Template__c WHERE Id = :second.Id].Active__c,
            'The letter that was off is still off.'
        );
    }

    /**
     * The lazy path that survives: an org issuing its first receipt with no letter of that kind
     * gets one, because a receipt that fails to generate is worse than a record created on the
     * issuing path. It is authorized by `Issue_Receipts`, the permission that authorizes the
     * receipt itself.
     */
    @IsTest
    static void issuingAReceiptOnAnOrgWithNoLettersStillProducesADocument() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            ReceiptTestDataFactory.setUpReceipting();
            delete [SELECT Id FROM Receipt_Template__c];
            ReceiptTemplateService.managePermission = false;
            Contact lin = GivingTestDataFactory.insertHouseholdContact(
                'The Lin Family',
                'Wei',
                'Lin'
            );
            Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                lin.Id,
                75,
                Date.newInstance(2026, 1, 5)
            );
            insert gift;

            Test.startTest();
            Receipt__c issued = ReceiptService.issueForGift(gift.Id);
            Test.stopTest();

            Assert.isNotNull(
                issued.Receipt_Number__c,
                'The donor gets their receipt rather than an error about a missing letter.'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Receipt_Template__c
                    WHERE Type__c = :ReceiptNumberSequence.TYPE_PER_GIFT AND Active__c = TRUE
                ],
                'The shipped per gift letter was materialized once, without Manage Nonprofit Settings.'
            );
        }
    }
}
