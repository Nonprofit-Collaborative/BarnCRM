/**
 * The soft credit and tribute an imported gift can carry (R-GI5, R-GI6), and what an undo of
 * a gift import keeps (R-GI9). Run as Maria, who holds the admin permission sets.
 */
@IsTest
private class GiftImportCreditsTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    /** One row: Ana gives 100 on 15 March, Ben is on the row too, with these extra columns. */
    private static void given(Map<String, String> extra) {
        TestDataFactory.defaultSettings();
        GivingTestDataFactory.insertDefaultFund();
        ImportMapping mapping = new ImportMapping();
        Map<String, String> row = new Map<String, String>{
            'Contact1.Email' => 'ana@example.org',
            'Contact1.LastName' => 'Ramirez',
            'Contact2.Email' => 'ben@example.org',
            'Contact2.LastName' => 'Ramirez',
            'Gift.Amount__c' => '100',
            'Gift.Gift_Date__c' => '2026-03-15',
            'Gift.Type__c' => 'Cash'
        };
        row.putAll(extra);
        for (String target : row.keySet()) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });
    }

    private static void commitAsMaria() {
        System.runAs(maria()) {
            Test.startTest();
            ImportRowProcessor.process(
                batch,
                template,
                ImportMapping.parse(template.Column_Mapping_JSON__c),
                ImportTestDataFactory.reload(batch.Id),
                false
            );
            Test.stopTest();
        }
    }

    private static Import_Row__c row() {
        return [
            SELECT Status__c, Error_Message__c, Gift_Id__c, Soft_Credit_Id__c, Contact_2__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
        ];
    }

    @IsTest
    static void theSecondPersonIsSoftCreditedWithTheWholeGift() {
        given(new Map<String, String>{ 'SoftCredit.Role__c' => 'solicitor' });

        commitAsMaria();

        Import_Row__c after = row();
        Assert.areEqual(
            ImportRowProcessor.STATUS_CREATED,
            after.Status__c,
            'Created: ' + after.Error_Message__c
        );
        Soft_Credit__c credit = [
            SELECT Contact__c, Role__c, Amount__c
            FROM Soft_Credit__c
            WHERE Id = :after.Soft_Credit_Id__c
        ];
        Assert.areEqual(after.Contact_2__c, credit.Contact__c, 'Ben is credited.');
        Assert.areEqual('Solicitor', credit.Role__c, 'In any capitals.');
        Assert.isTrue(credit.Amount__c == 100, 'With the whole gift.');
    }

    @IsTest
    static void aCreditThePackageAlreadyMadeIsNotMadeTwice() {
        given(new Map<String, String>{ 'SoftCredit.Role__c' => 'Household Member' });

        commitAsMaria();

        Import_Row__c after = row();
        Assert.areEqual(
            ImportRowProcessor.STATUS_CREATED,
            after.Status__c,
            'Created: ' + after.Error_Message__c
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Soft_Credit__c
                WHERE Contact__c = :after.Contact_2__c AND Role__c = 'Household Member'
            ],
            'One household member credit for Ben, however it was made.'
        );
    }

    @IsTest
    static void aTributeComesWithTheGift() {
        given(
            new Map<String, String>{
                'Tribute.Type__c' => 'in memory of',
                'Tribute.Honoree_Name__c' => 'Rosa Ramirez',
                'Tribute.Message__c' => 'With love'
            }
        );

        commitAsMaria();

        Import_Row__c after = row();
        Assert.areEqual(
            ImportRowProcessor.STATUS_CREATED,
            after.Status__c,
            'Created: ' + after.Error_Message__c
        );
        Tribute__c tribute = [SELECT Type__c, Honoree_Name__c, Gift__c FROM Tribute__c];
        Assert.areEqual('In memory of', tribute.Type__c, 'Its type.');
        Assert.areEqual(String.valueOf(tribute.Gift__c), after.Gift_Id__c, 'On the row\'s gift.');
    }

    @IsTest
    static void aCreditOrTributeThatCannotBeIsRefusedBeforeTheGift() {
        given(new Map<String, String>{ 'SoftCredit.Role__c' => 'Other' });

        commitAsMaria();

        Import_Row__c after = row();
        Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, after.Status__c, 'Refused.');
        Assert.areEqual(Label.Giving_Import_ErrorCustomRoleMissing, after.Error_Message__c, 'Why.');
        Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'And no gift was made for it.');
    }

    @IsTest
    static void anUndoKeepsAReceiptedGiftAndItsDonor() {
        given(new Map<String, String>());
        commitAsMaria();
        Import_Row__c after = row();
        Gift__c gift = [SELECT Id, Donor_Contact__c FROM Gift__c WHERE Id = :after.Gift_Id__c];
        insert new Receipt__c(
            Receipt_Number__c = 'R-TEST-1',
            Type__c = 'Per gift',
            Statement_Year__c = 2026,
            Status__c = 'Void',
            Void_Reason__c = 'Issued to the wrong address.',
            Voided_On__c = Datetime.now(),
            Gift__c = gift.Id,
            Donor_Contact__c = gift.Donor_Contact__c,
            Issue_Date__c = Date.today()
        );
        GiftImportProcessor processor = new GiftImportProcessor();

        Map<Id, String> gifts = processor.reasonsToKeep(
            batch.Id,
            Gift__c.SObjectType,
            new Set<Id>{ gift.Id }
        );
        Map<Id, String> people = processor.reasonsToKeep(
            batch.Id,
            Contact.SObjectType,
            new Set<Id>{ gift.Donor_Contact__c, after.Contact_2__c }
        );

        Assert.areEqual(Label.Giving_Import_UndoKeptReceipted, gifts.get(gift.Id), 'Even void.');
        Assert.areEqual(
            Label.Giving_Import_UndoKeptDonor,
            people.get(gift.Donor_Contact__c),
            'Ana.'
        );
        Assert.isTrue(
            processor.taggedObjects().contains(Gift__c.SObjectType),
            'Gifts are what the import tags.'
        );
    }

    @IsTest
    static void anUndoKeepsAGiftAnIssuedStatementLists() {
        given(new Map<String, String>());
        commitAsMaria();
        Gift__c gift = [SELECT Id, Donor_Contact__c FROM Gift__c];
        insert new Receipt__c(
            Receipt_Number__c = 'S-TEST-1',
            Type__c = 'Consolidated statement',
            Status__c = 'Issued',
            Statement_Year__c = 2026,
            Donor_Contact__c = gift.Donor_Contact__c,
            Issue_Date__c = Date.today()
        );

        Map<Id, String> keep = new GiftImportProcessor()
            .reasonsToKeep(batch.Id, Gift__c.SObjectType, new Set<Id>{ gift.Id });

        Assert.areEqual(
            Label.Giving_Import_UndoKeptStatement,
            keep.get(gift.Id),
            'The 2026 statement.'
        );
    }
}
