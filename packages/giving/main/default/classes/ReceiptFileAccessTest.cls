/**
 * Who can read a receipt document, and through what (ADR-0034).
 *
 * A `ContentDocumentLink` grants access to a file through the record it names, not through
 * `Receipt__c`. So the links a receipt's file carries are its access control list, and this class
 * asserts that list rather than the permission sets, which were already correct and were not the
 * thing letting the wrong people in.
 *
 * The defect these cover: the file was linked to the donor Contact and the donor Account as well
 * as to the receipt, and a Program Staff or Volunteer Coordinator user, who holds `BarnCRM_Staff`
 * and no Giving permission set at all, has Read on Account and Contact. A donor's year end
 * statement, listing their whole giving history, the organization's EIN and the signer's name, was
 * in the Files related list of a record those users open every day.
 *
 * **None of this has been executed against an org.** File sharing is decided by the platform at
 * query time, so what these tests assert about the links is exact and offline verifiable, while
 * what the third test asserts about what another user can see is the platform behaviour that a
 * real org has to confirm.
 */
@IsTest
private class ReceiptFileAccessTest {
    private static final Integer YEAR = 2026;

    /**
     * A year end statement is reachable only through its receipt, which every Giving permission set
     * grants Read on and no role can edit (R-RC10).
     */
    @IsTest
    static void aYearEndStatementIsLinkedOnlyToItsReceipt() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            ReceiptTestDataFactory.setUpReceipting();
            Contact reyes = GivingTestDataFactory.insertHouseholdContact(
                'The Reyes Family',
                'Ana',
                'Reyes'
            );
            insert ReceiptTestDataFactory.plainCashGift(
                reyes.Id,
                250,
                Date.newInstance(YEAR, 3, 1)
            );
            Receipt__c statement = issueOneStatement();

            Set<Id> linked = linkedEntitiesFor(statement.Content_Document_Id__c);

            Assert.areEqual(
                new Set<Id>{ statement.Id },
                linked,
                'A statement is linked to its receipt and to nothing else, because a link is what ' +
                'grants access to the file.'
            );
            Assert.isFalse(
                linked.contains(reyes.AccountId),
                'It is not linked to the donor household, whose record every Core role can read.'
            );
        }
    }

    /**
     * A per gift receipt is linked to its gift as well, because the gift is a Giving record: a user
     * who can open the gift is a user the receipt was always meant for.
     */
    @IsTest
    static void aPerGiftReceiptIsLinkedToItsReceiptAndItsGiftAndNothingElse() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            ReceiptTestDataFactory.setUpReceipting();
            Contact haddad = GivingTestDataFactory.insertHouseholdContact(
                'The Haddad Family',
                'Nour',
                'Haddad'
            );
            Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                haddad.Id,
                300,
                Date.newInstance(YEAR, 4, 2)
            );
            insert gift;

            Test.startTest();
            Receipt__c issued = ReceiptService.issueForGift(gift.Id);
            Test.stopTest();

            Receipt__c stored = [
                SELECT Content_Document_Id__c
                FROM Receipt__c
                WHERE Id = :issued.Id
            ];
            Set<Id> linked = linkedEntitiesFor(stored.Content_Document_Id__c);

            Assert.areEqual(
                new Set<Id>{ issued.Id, gift.Id },
                linked,
                'The receipt and the gift, which are the two records a Giving permission set governs.'
            );
            Assert.isFalse(
                linked.contains(haddad.Id),
                'Not the donor Contact: Read on a Contact is not permission to read their tax document.'
            );
            Assert.isFalse(
                linked.contains(haddad.AccountId),
                'Not the donor household either, for the same reason.'
            );
        }
    }

    /**
     * The one that matters. Priya coordinates volunteers, holds `BarnCRM_Staff` and no Giving
     * permission set, and can open the donor's household record. She must not be able to reach the
     * household's year end statement from it.
     */
    @IsTest
    static void programStaffWithNoGivingPermissionSetCannotReachAStatementThroughTheDonor() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            User coordinator = TestDataFactory.createUser(
                'Priya',
                new List<String>{ 'BarnCRM_Staff' }
            );
            ReceiptTestDataFactory.setUpReceipting();
            Contact osei = GivingTestDataFactory.insertHouseholdContact(
                'The Osei Family',
                'Kofi',
                'Osei'
            );
            insert ReceiptTestDataFactory.plainCashGift(osei.Id, 400, Date.newInstance(YEAR, 5, 1));
            Receipt__c statement = issueOneStatement();
            Id household = osei.AccountId;
            Id documentId = statement.Content_Document_Id__c;
            // Whether staff can open a household somebody else entered is the org's sharing model,
            // so Priya is given this one: what is under test is the file, not the household.
            update new Account(Id = household, OwnerId = coordinator.Id);

            List<Account> householdsSheCanSee;
            List<ContentDocumentLink> linksOnTheHousehold;
            List<ContentDocument> documentsSheCanSee;
            System.runAs(coordinator) {
                householdsSheCanSee = [SELECT Id FROM Account WHERE Id = :household];
                linksOnTheHousehold = [
                    SELECT ContentDocumentId
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :household
                ];
                documentsSheCanSee = [SELECT Id FROM ContentDocument WHERE Id = :documentId];
            }

            Assert.areEqual(
                1,
                householdsSheCanSee.size(),
                'She can open the household, which is the whole reason this test exists: the record ' +
                'is hers to see and the tax document is not.'
            );
            Assert.isTrue(
                linksOnTheHousehold.isEmpty(),
                'No receipt file hangs off the donor record, so the Files related list has nothing ' +
                'of the donor tax history in it.'
            );
            Assert.isTrue(
                documentsSheCanSee.isEmpty(),
                'And the file itself is out of reach: her only route to it would have been a link.'
            );
        }
    }

    /**
     * Every link a receipt document carries grants viewing and no more, and to internal users only.
     * Viewer is the ceiling ADR-0010 needs: an issued document is not editable by anybody.
     */
    @IsTest
    static void everyReceiptDocumentLinkIsViewerOnlyAndInternal() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            ReceiptTestDataFactory.setUpReceipting();
            Contact diallo = GivingTestDataFactory.insertHouseholdContact(
                'The Diallo Family',
                'Awa',
                'Diallo'
            );
            Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                diallo.Id,
                90,
                Date.newInstance(YEAR, 6, 6)
            );
            insert gift;

            Test.startTest();
            Receipt__c issued = ReceiptService.issueForGift(gift.Id);
            Test.stopTest();

            Receipt__c stored = [
                SELECT Content_Document_Id__c
                FROM Receipt__c
                WHERE Id = :issued.Id
            ];
            List<ContentDocumentLink> links = linksOtherThanTheOwner(stored.Content_Document_Id__c);

            Assert.areEqual(2, links.size(), 'The receipt and the gift, which is what was linked.');
            for (ContentDocumentLink link : links) {
                Assert.areEqual(
                    'V',
                    link.ShareType,
                    'Viewer, so record edit access can never become file edit access on a document ' +
                    'that is immutable once issued.'
                );
                // An org with external users is given InternalUsers. An org with none refuses that
                // value, and AllUsers there reaches the same internal users (ADR-0034), so AllUsers is
                // accepted only when the platform refused InternalUsers in this very run.
                Assert.areEqual(
                    ReceiptWriter.orgRefusesInternalOnlyLinks == true
                        ? 'AllUsers'
                        : 'InternalUsers',
                    link.Visibility,
                    'A receipt is an internal document: no external user reaches one through a link ' +
                    'this package created.'
                );
            }
        }
    }

    /**
     * The rule lives in the writer, so a future caller cannot widen the audience by passing one
     * more id. This is a code defect rather than a user error, so it throws.
     */
    @IsTest
    static void linkingAReceiptDocumentToADonorRecordIsRefused() {
        ReceiptTestDataFactory.setUpReceipting();
        Contact ferreira = GivingTestDataFactory.insertHouseholdContact(
            'The Ferreira Family',
            'Luis',
            'Ferreira'
        );

        Test.startTest();
        try {
            ReceiptWriter.storeDocument(
                'HFH-2026-000099',
                Blob.valueOf('<p>A statement</p>'),
                new List<Id>{ ferreira.Id }
            );
            Assert.fail('A receipt document was linked to a donor Contact.');
        } catch (ReceiptWriter.ReceiptFileLinkException refused) {
            Assert.isTrue(
                refused.getMessage().contains('Contact'),
                'The message names the object that was refused, so the mistake is obvious: ' +
                refused.getMessage()
            );
        }
        Test.stopTest();
    }

    // ----------------------------------------------------------------------- helpers

    /** One year end statement, issued the way the year end run issues them. */
    private static Receipt__c issueOneStatement() {
        Receipt_Run__c run = new Receipt_Run__c(
            Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
            Statement_Year__c = YEAR,
            Status__c = ReceiptRunService.STATUS_QUEUED,
            Donors_Processed__c = 0,
            Receipts_Issued__c = 0,
            Errors__c = 0
        );
        insert run;

        Test.startTest();
        Database.executeBatch(new ReceiptStatementBatch(YEAR, run.Id), ReceiptStatementBatch.SCOPE);
        Test.stopTest();

        List<Receipt__c> issued = [
            SELECT Id, Content_Document_Id__c, Donor_Account__c
            FROM Receipt__c
            WHERE Type__c = :ReceiptNumberSequence.TYPE_STATEMENT AND Status__c = 'Issued'
        ];
        Assert.areEqual(1, issued.size(), 'The run issued the one statement this test reads.');
        Assert.isNotNull(
            issued[0].Content_Document_Id__c,
            'The statement has a stored file, which is the thing whose access is being asserted.'
        );
        return issued[0];
    }

    /**
     * The records a stored document is reachable through, other than its owner.
     *
     * The platform links every file to the user who owns it, the person who issued the receipt,
     * and that link is ownership rather than a grant this package makes: the owner holds the file
     * whether or not the link is listed (ADR-0034). It is the one link left out, and only when it
     * names the document's own owner, so a link to any other user still shows up here.
     */
    private static Set<Id> linkedEntitiesFor(Id documentId) {
        Set<Id> linked = new Set<Id>();
        for (ContentDocumentLink link : linksOtherThanTheOwner(documentId)) {
            linked.add(link.LinkedEntityId);
        }
        return linked;
    }

    private static List<ContentDocumentLink> linksOtherThanTheOwner(Id documentId) {
        Id owner = [SELECT OwnerId FROM ContentDocument WHERE Id = :documentId].OwnerId;
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :documentId
        ]) {
            if (link.LinkedEntityId != owner) {
                links.add(link);
            }
        }
        return links;
    }
}
