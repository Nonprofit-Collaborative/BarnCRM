/**
 * The receipt lock, from both sides.
 *
 * ADR-0010 says a receipted gift stops changing. ADR-0024 says that rule is not a setting: it
 * runs from an automation the console cannot switch off and a pause does not suspend, and the
 * only way past it is a custom permission the package grants to nobody, every use of which is
 * written to the Error Log.
 *
 * So these tests are about David, who cannot change a receipted gift however he tries, and about
 * the one afternoon Maria is given the override permission in Setup to correct a receipt that
 * was issued against the wrong donor, and finds that BarnCRM wrote down what she did.
 */
@IsTest(testFor='ApexClass:GiftReceiptLockHandler')
private class GiftReceiptLockHandlerTest {
    private static final String OVERRIDE_PERMISSION = 'Override_Receipt_Lock';
    private static final String RECEIPT_NUMBER = 'R-2026-000042';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            Contact donor = GivingTestDataFactory.insertHouseholdContact(
                'The Nolan Family',
                'Ana',
                'Nolan'
            );
            GivingTestDataFactory.insertHouseholdContact('The Okafor Family', 'Ben', 'Okafor');
            Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 250);
            gift.Gift_Date__c = Date.newInstance(2026, 3, 1);
            insert gift;
            // The receipting feature's door is the only way a number reaches a gift, and putting one
            // there is what locks the gift (ADR-0033).
            GiftService.recordReceiptNumbers(new Map<Id, String>{ gift.Id => RECEIPT_NUMBER });
        }
    }

    private static Gift__c receiptedGift() {
        return [
            SELECT
                Id,
                Amount__c,
                Gift_Date__c,
                Donor_Contact__c,
                Donor_Account__c,
                Receipt_Number__c
            FROM Gift__c
            WHERE Receipt_Number__c = :RECEIPT_NUMBER
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    private static Contact otherDonor() {
        return [SELECT Id FROM Contact WHERE LastName = 'Okafor' LIMIT 1];
    }

    /**
     * The permission set an administrator builds in Setup for the length of one correction, and
     * takes away again: the override permission, and Edit on Gift Receipt Number, which the
     * packaged sets make read only to everyone (ADR-0033) and which the Gifts admin guide has the
     * administrator grant in the same set.
     */
    private static User userHoldingTheOverride() {
        User maria = TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
        grantInSetup(maria, true);
        return maria;
    }

    /**
     * A permission set built in Setup and assigned to one person: Edit on Gift Receipt Number,
     * and the override permission when asked for. Written inside `runAs` because a permission set
     * is a setup object and the test has already touched gifts.
     */
    private static void grantInSetup(User person, Boolean withOverride) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet granted = new PermissionSet(
                Name = withOverride ? 'Receipt_Lock_Override_Test' : 'Receipt_Number_Edit_Test',
                Label = withOverride ? 'Receipt lock override (test)' : 'Receipt number edit (test)'
            );
            insert granted;
            insert new FieldPermissions(
                ParentId = granted.Id,
                SobjectType = 'Gift__c',
                Field = 'Gift__c.Receipt_Number__c',
                PermissionsRead = true,
                PermissionsEdit = true
            );
            if (withOverride) {
                insert new SetupEntityAccess(
                    ParentId = granted.Id,
                    SetupEntityId = overridePermissionId()
                );
            }
            insert new PermissionSetAssignment(
                AssigneeId = person.Id,
                PermissionSetId = granted.Id
            );
        }
    }

    private static Id overridePermissionId() {
        List<CustomPermission> permissions = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = :OVERRIDE_PERMISSION
            LIMIT 1
        ];
        Assert.areEqual(
            1,
            permissions.size(),
            'The package ships the override permission, or there is nothing to grant.'
        );
        return permissions[0].Id;
    }

    /**
     * Makes records belong to the person a test runs as. Gifts ship private, and who can reach a
     * person somebody else entered is the org's sharing model, which differs from org to org.
     * Handing the person the records keeps these tests about the lock and the permissions, not
     * about sharing. A contact's household account goes with the contact, for an org where
     * contacts are shared through their account.
     */
    private static void handTo(User person, List<Id> recordIds) {
        List<Account> households = new List<Account>();
        for (Contact record : [
            SELECT AccountId
            FROM Contact
            WHERE Id IN :recordIds AND AccountId != NULL
        ]) {
            households.add(new Account(Id = record.AccountId, OwnerId = person.Id));
        }
        update households;
        List<SObject> handed = new List<SObject>();
        for (Id recordId : recordIds) {
            SObject owned = recordId.getSObjectType().newSObject(recordId);
            owned.put('OwnerId', person.Id);
            handed.add(owned);
        }
        update handed;
        // The save above asked whether the running administrator holds the override, and the
        // answer is kept for the transaction. The person the test runs as next is asked afresh.
        GiftService.receiptLockOverride = null;
    }

    private static String refusalFrom(Gift__c gift) {
        try {
            update gift;
            return null;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
    }

    @IsTest
    static void theLockRefusesEachOfTheFourChangesThatWouldContradictTheReceipt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = receiptedGift();
            Id otherPerson = otherDonor().Id;

            Test.startTest();
            Gift__c amountChange = new Gift__c(Id = gift.Id, Amount__c = 300);
            String amountRefusal = refusalFrom(amountChange);

            Gift__c dateChange = new Gift__c(
                Id = gift.Id,
                Gift_Date__c = Date.newInstance(2026, 4, 1)
            );
            String dateRefusal = refusalFrom(dateChange);

            Gift__c donorChange = new Gift__c(Id = gift.Id, Donor_Contact__c = otherPerson);
            String donorRefusal = refusalFrom(donorChange);

            Gift__c numberChange = new Gift__c(Id = gift.Id, Receipt_Number__c = 'R-2026-000099');
            String numberRefusal = refusalFrom(numberChange);
            Test.stopTest();

            Assert.isTrue(
                amountRefusal != null && amountRefusal.contains(Label.Giving_Gift_ReceiptLocked),
                'Changing the amount contradicts the document the donor holds.'
            );
            Assert.isTrue(
                dateRefusal != null && dateRefusal.contains(Label.Giving_Gift_ReceiptLocked),
                'So does changing the date the receipt states.'
            );
            Assert.isTrue(
                donorRefusal != null && donorRefusal.contains(Label.Giving_Gift_ReceiptLocked),
                'So does moving the gift to another donor.'
            );
            Assert.isTrue(
                numberRefusal != null &&
                numberRefusal.contains(Label.Giving_Gift_ReceiptNumberLocked),
                'And the number itself is locked, or the lock could be lifted in two saves.'
            );

            Gift__c unchanged = receiptedGift();
            Assert.areEqual(
                250,
                unchanged.Amount__c,
                'Nothing was saved: the amount is as receipted.'
            );
            Assert.areEqual(
                Date.newInstance(2026, 3, 1),
                unchanged.Gift_Date__c,
                'And so is the date.'
            );
            Assert.areEqual(
                RECEIPT_NUMBER,
                unchanged.Receipt_Number__c,
                'And the receipt number is the one the donor is holding.'
            );
        }
    }

    @IsTest
    static void theLockRefusesToDeleteAReceiptedGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = receiptedGift();

            Test.startTest();
            String refusal;
            try {
                delete gift;
            } catch (DmlException refused) {
                refusal = refused.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.isTrue(
                refusal != null && refusal.contains(Label.Giving_Gift_ReceiptedGiftNotDeletable),
                'A receipted gift is corrected by a refund or a reissue, never deleted.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Gift__c WHERE Receipt_Number__c = :RECEIPT_NUMBER],
                'And the gift is still there.'
            );
        }
    }

    @IsTest
    static void theLockStillRefusesWhileAllAutomationIsPaused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.pausedSettings(2);
            AutomationControl.clearCache();
            Gift__c gift = receiptedGift();

            Test.startTest();
            String refusal = refusalFrom(new Gift__c(Id = gift.Id, Amount__c = 400));
            Test.stopTest();

            Assert.isTrue(
                refusal != null && refusal.contains(Label.Giving_Gift_ReceiptLocked),
                'The pause stops BarnCRM filling things in, never stops it refusing something.'
            );
            Assert.areEqual(
                250,
                receiptedGift().Amount__c,
                'So the amount a donor was receipted for did not move during the pause.'
            );
        }
    }

    @IsTest
    static void theOverridePermissionLetsTheCorrectionThroughAndRecordsIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = receiptedGift();
            Id otherPerson = otherDonor().Id;
            User maria = userHoldingTheOverride();
            handTo(maria, new List<Id>{ gift.Id });

            Test.startTest();
            System.runAs(maria) {
                update new Gift__c(
                    Id = gift.Id,
                    Amount__c = 300,
                    Gift_Date__c = Date.newInstance(2026, 4, 1),
                    Donor_Contact__c = otherPerson
                );
            }
            Test.stopTest();

            Gift__c corrected = receiptedGift();
            Assert.areEqual(300, corrected.Amount__c, 'The correction was saved.');
            Assert.areEqual(
                Date.newInstance(2026, 4, 1),
                corrected.Gift_Date__c,
                'Every locked value the save carried was allowed through, not just the first.'
            );
            Assert.areEqual(otherPerson, corrected.Donor_Contact__c, 'Including the donor.');

            List<Error_Log__c> logged = [
                SELECT Message__c, Context__c, Severity__c, User__c
                FROM Error_Log__c
                WHERE Severity__c = :ErrorLogger.SEVERITY_WARNING
            ];
            Assert.areEqual(1, logged.size(), 'One overridden gift, one Error Log entry.');
            Assert.areEqual(
                'Receipt lock override',
                logged[0].Context__c,
                'Filed where an auditor looking for overrides will find it.'
            );
            Assert.areEqual(maria.Id, logged[0].User__c, 'Naming the person who made the change.');
            Assert.isTrue(
                logged[0].Message__c.contains(String.valueOf(gift.Id)),
                'The entry names the gift.'
            );
            Assert.isTrue(
                logged[0].Message__c.contains(RECEIPT_NUMBER),
                'And the receipt the donor is holding.'
            );
            Assert.isTrue(
                logged[0].Message__c.contains(Gift__c.Amount__c.getDescribe().getLabel()) &&
                    logged[0].Message__c.contains(Gift__c.Gift_Date__c.getDescribe().getLabel()) &&
                    logged[0]
                        .Message__c.contains(Gift__c.Donor_Contact__c.getDescribe().getLabel()),
                'And each value that moved, so the change can be reconstructed: ' +
                logged[0].Message__c
            );
        }
    }

    @IsTest
    static void theOverridePermissionLetsAReceiptedGiftBeDeletedAndRecordsThat() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = receiptedGift();
            User maria = userHoldingTheOverride();
            handTo(maria, new List<Id>{ gift.Id });

            Test.startTest();
            System.runAs(maria) {
                delete gift;
            }
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Gift__c WHERE Receipt_Number__c = :RECEIPT_NUMBER],
                'The deletion went through for the one person holding the permission.'
            );
            List<Error_Log__c> logged = [
                SELECT Message__c, Severity__c
                FROM Error_Log__c
                WHERE Context__c = 'Receipt lock override'
            ];
            Assert.areEqual(1, logged.size(), 'And it was recorded.');
            Assert.areEqual(
                ErrorLogger.SEVERITY_WARNING,
                logged[0].Severity__c,
                'At Warning, which is what the Error Log page filters on.'
            );
            Assert.isTrue(
                logged[0].Message__c.contains(Label.Giving_Gift_OverrideDeleted),
                'Saying what was done, not just that something was: ' + logged[0].Message__c
            );
        }
    }

    @IsTest
    static void theOverrideDoesNotReachTheReversalRefusal() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = otherDonor();
            Gift__c original = GivingTestDataFactory.buildGift(person.Id, 250);
            insert original;
            Gift__c reversal = GivingTestDataFactory.buildGift(person.Id, -250);
            reversal.Original_Gift__c = original.Id;
            insert reversal;
            User maria = userHoldingTheOverride();
            // Maria recorded the refund herself, so both halves of it are hers to reach.
            handTo(maria, new List<Id>{ original.Id, reversal.Id });

            String refusal;
            Test.startTest();
            System.runAs(maria) {
                try {
                    delete original;
                    Assert.fail(
                        'The reversal refusal is not the receipt lock, so it still applies.'
                    );
                } catch (DmlException expected) {
                    refusal = expected.getDmlMessage(0);
                }
            }
            Test.stopTest();

            Assert.isTrue(
                refusal != null && refusal.contains(Label.Giving_Gift_ReversedGiftNotDeletable),
                'Refused for the reason R-G3 gives, not the receipt one: ' + refusal
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Gift__c WHERE Id = :original.Id],
                'Original_Gift__c is a lookup with SetNull, so a deletion here would leave the ' +
                'negative gift standing with nothing to say what it reverses.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Receipt lock override'],
                'Nothing was overridden, so nothing was recorded as overridden.'
            );
        }
    }

    /**
     * David, who enters the gifts and has no business inventing receipt numbers.
     */
    private static User fundraiser() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
    }

    @IsTest
    static void staffCannotTypeAReceiptNumberOntoAGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = otherDonor();
            Gift__c plain = GivingTestDataFactory.buildGift(person.Id, 120);
            insert plain;
            User david = fundraiser();
            handTo(david, new List<Id>{ person.Id, plain.Id });

            Boolean editable = true;
            System.runAs(david) {
                editable = Schema.SObjectType.Gift__c.fields.Receipt_Number__c.isUpdateable();
            }
            // Field level security refuses the write before any trigger runs, so to reach the rule
            // behind it David is granted the field, the way a well meaning administrator might.
            grantInSetup(david, false);

            String refusal;
            Test.startTest();
            System.runAs(david) {
                refusal = refusalFrom(
                    new Gift__c(Id = plain.Id, Receipt_Number__c = 'R-2026-000777')
                );
            }
            Test.stopTest();

            Assert.isFalse(
                editable,
                'Giving Staff reads the receipt number and does not write it: the packaged permission ' +
                'sets make it read only, so the field is not offered for editing anywhere.'
            );
            Assert.isTrue(
                refusal != null && refusal.contains(Label.Giving_Gift_ReceiptNumberNotIssuedByHand),
                'And the refusal does not depend on that: a number typed onto a gift is refused ' +
                    'whoever was granted the field, because it came from no sequence: ' +
                    refusal
            );
            Assert.areEqual(
                null,
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :plain.Id].Receipt_Number__c,
                'The gift carries no number, so it is neither locked nor unreceiptable: Issue ' +
                'Receipt still works on it.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Receipt lock override'],
                'Nothing was overridden, so nothing was recorded as overridden.'
            );
        }
    }

    @IsTest
    static void staffCannotCreateAGiftThatAlreadyCarriesAReceiptNumber() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = otherDonor();
            User david = fundraiser();
            handTo(david, new List<Id>{ person.Id });
            // Granted the field, as above, so that what refuses the save is the rule and not field
            // level security.
            grantInSetup(david, false);
            Gift__c minted = GivingTestDataFactory.buildGift(person.Id, 90);
            minted.Receipt_Number__c = 'R-2026-000778';

            String refusal;
            Test.startTest();
            System.runAs(david) {
                try {
                    insert minted;
                } catch (DmlException refused) {
                    refusal = refused.getDmlMessage(0);
                }
            }
            Test.stopTest();

            Assert.isTrue(
                refusal != null && refusal.contains(Label.Giving_Gift_ReceiptNumberNotIssuedByHand),
                'Creating the gift with the number in place is the same tamper as typing it on ' +
                    'afterwards, so it is refused the same way: ' +
                    refusal
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Gift__c WHERE Receipt_Number__c = 'R-2026-000778'],
                'And no gift was created holding a number the sequence has never issued.'
            );
        }
    }

    @IsTest
    static void theReceiptingFeatureStillWritesTheNumber() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = otherDonor();
            Gift__c plain = GivingTestDataFactory.buildGift(person.Id, 300);
            insert plain;
            User david = fundraiser();
            // The writer keeps the running user's sharing: David receipts a gift he can reach.
            handTo(david, new List<Id>{ person.Id, plain.Id });

            Test.startTest();
            System.runAs(david) {
                GiftService.recordReceiptNumbers(
                    new Map<Id, String>{ plain.Id => 'R-2026-000501' }
                );
            }
            Test.stopTest();

            Assert.areEqual(
                'R-2026-000501',
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :plain.Id].Receipt_Number__c,
                'The one door through the lock still opens, for the same staff user, even though ' +
                    'the field is read only to them: the write goes through GiftReceiptNumberWriter in ' +
                    'system mode (ADR-0021, ADR-0033).'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Receipt lock override'],
                'Issuing a receipt is not an override, so it is not logged as one.'
            );
        }
    }

    @IsTest
    static void theRenumberAllowanceReachesOnlyTheGiftBeingRenumbered() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c receipted = receiptedGift();
            Contact person = otherDonor();
            Gift__c bystander = GivingTestDataFactory.buildGift(person.Id, 75);
            insert bystander;

            // The window recordReceiptNumbers opens, held open here so that a second gift can be
            // saved inside it, which is what a nested update from an after-update handler does.
            GiftService.giftsBeingRenumbered = new Set<Id>{ receipted.Id };

            Test.startTest();
            List<Database.SaveResult> results = Database.update(
                new List<Gift__c>{
                    new Gift__c(Id = receipted.Id, Receipt_Number__c = 'R-2026-000043'),
                    new Gift__c(Id = bystander.Id, Receipt_Number__c = 'R-2026-000044')
                },
                false
            );
            Test.stopTest();

            Assert.isTrue(results[0].isSuccess(), 'The gift being renumbered was renumbered.');
            Assert.isFalse(
                results[1].isSuccess(),
                'The gift that was not being renumbered was refused, because the allowance names ' +
                'the gifts it is for rather than lifting the rule for the whole transaction.'
            );
            Assert.areEqual(
                Label.Giving_Gift_ReceiptNumberNotIssuedByHand,
                results[1].getErrors()[0].getMessage(),
                'And refused for the right reason: that number came from no sequence.'
            );
            Assert.areEqual(
                'R-2026-000043',
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :receipted.Id].Receipt_Number__c,
                'The reissued number is on the gift it belongs to.'
            );
            Assert.areEqual(
                null,
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :bystander.Id].Receipt_Number__c,
                'And the bystander is still an unreceipted gift.'
            );
        }
    }

    @IsTest
    static void theOverrideStillRecoversAGiftNumberedByMistake() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            // The administrator grants Edit on Gift Receipt Number in the same temporary permission
            // set that carries the override permission (ADR-0033, and the Gifts admin guide says so
            // step by step), which is what userHoldingTheOverride builds.
            Gift__c gift = receiptedGift();
            User maria = userHoldingTheOverride();
            handTo(maria, new List<Id>{ gift.Id });

            Test.startTest();
            System.runAs(maria) {
                update new Gift__c(Id = gift.Id, Receipt_Number__c = null);
            }
            Test.stopTest();

            Assert.areEqual(
                null,
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :gift.Id].Receipt_Number__c,
                'The documented override still clears a number, which is what unsticks a gift that ' +
                'was numbered by mistake: with the number gone, Issue Receipt can receipt it.'
            );
            List<Error_Log__c> logged = [
                SELECT Message__c, Severity__c
                FROM Error_Log__c
                WHERE Context__c = 'Receipt lock override'
            ];
            Assert.areEqual(1, logged.size(), 'And the recovery was recorded, once.');
            Assert.isTrue(
                logged[0].Message__c.contains(RECEIPT_NUMBER),
                'Naming the number that was on the gift, which is what an auditor asks about: ' +
                logged[0].Message__c
            );
        }
    }

    @IsTest
    static void aGiftWithNoReceiptIsStillAnOrdinaryEditableGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = otherDonor();
            Gift__c plain = GivingTestDataFactory.buildGift(person.Id, 60);
            insert plain;

            Test.startTest();
            plain.Amount__c = 75;
            update plain;
            Test.stopTest();

            Assert.areEqual(
                75,
                [SELECT Amount__c FROM Gift__c WHERE Id = :plain.Id].Amount__c,
                'The lock is about receipts, not about gifts: a mistyped amount is still correctable.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Receipt lock override'],
                'And nothing was overridden, so nothing was recorded.'
            );
        }
    }
}
