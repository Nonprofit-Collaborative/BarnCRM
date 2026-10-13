/**
 * The receipting screens' Apex: what the gift page offers, issuing, voiding and reissuing, the
 * letters, the statement runs and their history. Every refusal reaches the screen as a message
 * in words, never as a platform error.
 *
 * No PDF is made: the renderer is the recording stand-in from the receipting test data.
 */
@IsTest(testFor='ApexClass:ReceiptController')
private class ReceiptControllerTest {
    private static Gift__c insertGift(String familyName, Decimal amount) {
        Contact donor = GivingTestDataFactory.insertHouseholdContact(
            'The ' + familyName + ' Family',
            'Sam',
            familyName
        );
        Gift__c gift = ReceiptTestDataFactory.plainCashGift(
            donor.Id,
            amount,
            Date.newInstance(2026, 1, 8)
        );
        insert gift;
        return gift;
    }

    private static String refusalOf(Callable action) {
        try {
            action.call('run', null);
            return null;
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
    }

    private class Issue implements Callable {
        private Id giftId;
        Issue(Id giftId) {
            this.giftId = giftId;
        }
        public Object call(String action, Map<String, Object> args) {
            return ReceiptController.issue(giftId);
        }
    }

    private class VoidIt implements Callable {
        private Id receiptId;
        private String reason;
        VoidIt(Id receiptId, String reason) {
            this.receiptId = receiptId;
            this.reason = reason;
        }
        public Object call(String action, Map<String, Object> args) {
            return ReceiptController.voidReceipt(receiptId, reason);
        }
    }

    private class Reissue implements Callable {
        private Id receiptId;
        Reissue(Id receiptId) {
            this.receiptId = receiptId;
        }
        public Object call(String action, Map<String, Object> args) {
            return ReceiptController.voidAndReissue(receiptId, 'Wrong name');
        }
    }

    @IsTest
    static void aReceiptIsIssuedVoidedAndReissuedFromTheGiftPage() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Gift__c gift = insertGift('Okoye', 120);

                Test.startTest();
                ReceiptController.ReceiptView issued = ReceiptController.issue(gift.Id);
                ReceiptController.ReceiptView replacement = ReceiptController.voidAndReissue(
                    issued.id,
                    'Spelled the donor name wrong'
                );
                ReceiptController.GiftReceiptState state = ReceiptController.getGiftReceiptState(
                    gift.Id
                );
                Test.stopTest();

                Assert.areEqual(ReceiptService.STATUS_ISSUED, issued.status, 'Issued');
                Assert.areNotEqual(
                    issued.receiptNumber,
                    replacement.receiptNumber,
                    'The replacement takes a new number'
                );
                Assert.areEqual(
                    ReceiptService.STATUS_ISSUED,
                    replacement.status,
                    'The replacement is live'
                );
                Assert.areEqual(
                    2,
                    state.receipts.size(),
                    'The gift lists the original and its replacement'
                );
                Assert.isTrue(state.alreadyReceipted, 'The gift is receipted');
                Assert.isTrue(state.canIssue, 'The person may issue');
                Assert.areEqual(
                    ReceiptService.STATUS_VOID,
                    [SELECT Status__c FROM Receipt__c WHERE Id = :issued.id].Status__c,
                    'The first receipt is void'
                );
            }
        }
    }

    @IsTest
    static void aReceiptCanBeVoidedWithAReasonOnlyOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                ReceiptController.ReceiptView issued = ReceiptController.issue(
                    insertGift('Okoye', 80).Id
                );

                ReceiptController.ReceiptView voided = ReceiptController.voidReceipt(
                    issued.id,
                    'Donor asked'
                );

                Assert.areEqual(ReceiptService.STATUS_VOID, voided.status, 'Void');
                Assert.areEqual('Donor asked', voided.voidReason, 'With the reason given');
                Assert.isNotNull(voided.voidedOn, 'And when');
                Assert.areEqual(
                    Label.Giving_Receipt_AlreadyVoid,
                    refusalOf(new VoidIt(issued.id, 'Again')),
                    'A second void is refused in words'
                );
                Assert.areEqual(
                    Label.Giving_Receipt_VoidNeedsReason,
                    refusalOf(new VoidIt(issued.id, ' ')),
                    'A void with no reason is refused in words'
                );
            }
        }
    }

    @IsTest
    static void refusalsReachTheScreenAsTheMessagesTheyAre() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Gift__c gift = insertGift('Okoye', 60);
                ReceiptController.issue(gift.Id);
                Id missingReceipt = FakeIds.of(Receipt__c.SObjectType, 1);

                Assert.areEqual(
                    Label.Giving_Receipt_GiftAlreadyReceipted,
                    refusalOf(new Issue(gift.Id)),
                    'A receipted gift is not receipted twice'
                );
                Assert.areEqual(
                    Label.Giving_Receipt_NotFound,
                    refusalOf(new VoidIt(missingReceipt, 'x')),
                    'A receipt that is not there is named as missing'
                );
                Assert.areEqual(
                    Label.Giving_Receipt_NotFound,
                    refusalOf(new Reissue(missingReceipt)),
                    'So is one to reissue'
                );

                ReceiptService.issuePermission = false;
                Assert.areEqual(
                    Label.Giving_Receipt_NoPermission,
                    refusalOf(new Issue(gift.Id)),
                    'A person without the permission is told what to ask for'
                );
                Assert.isFalse(
                    ReceiptController.getGiftReceiptState(gift.Id).canIssue,
                    'And the page knows not to offer it'
                );
            }
        }
    }

    @IsTest
    static void theLettersCanBeListedEditedActivatedAndPreviewed() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Assert.isTrue(
                    ReceiptController.getCanManageTemplates(),
                    'This person may manage the letters'
                );
                List<ReceiptController.TemplateView> letters = ReceiptController.getTemplates();
                Assert.areEqual(2, letters.size(), 'A letter of each kind');
                Id perGift;
                for (ReceiptController.TemplateView letter : letters) {
                    if (letter.type == ReceiptNumberSequence.TYPE_PER_GIFT) {
                        perGift = letter.id;
                    }
                }

                ReceiptController.saveTemplate(perGift, '<p>Dear {{DonorName}}, thank you.</p>');
                Receipt_Template__c second = new Receipt_Template__c(
                    Name = 'Second letter',
                    Type__c = ReceiptNumberSequence.TYPE_PER_GIFT,
                    Active__c = false,
                    Body__c = ReceiptTestDataFactory.perGiftTemplateBody()
                );
                insert second;
                ReceiptController.activateTemplate(second.Id);

                Assert.areEqual(
                    '<p>Dear {{DonorName}}, thank you.</p>',
                    [SELECT Body__c FROM Receipt_Template__c WHERE Id = :perGift].Body__c,
                    'The edited body is saved'
                );
                Assert.isFalse(
                    [SELECT Active__c FROM Receipt_Template__c WHERE Id = :perGift].Active__c,
                    'Activating another letter of the kind switches this one off'
                );
                Assert.isTrue(
                    [SELECT Active__c FROM Receipt_Template__c WHERE Id = :second.Id].Active__c,
                    'And the chosen one on'
                );
                Assert.isTrue(
                    ReceiptController.previewTemplate(
                            ReceiptNumberSequence.TYPE_STATEMENT,
                            ReceiptTestDataFactory.statementTemplateBody()
                        )
                        .contains(Label.Giving_Receipt_PreviewDonor),
                    'The statement preview names the sample donor'
                );
                Assert.isFalse(
                    ReceiptController.restoreDefaultTemplates().isEmpty(),
                    'Restoring the shipped letters returns the list'
                );
            }
        }
    }

    @IsTest
    static void letterEditsThatCannotBeSavedAreRefusedInWords() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Id perGift = [
                    SELECT Id
                    FROM Receipt_Template__c
                    WHERE Type__c = :ReceiptNumberSequence.TYPE_PER_GIFT
                    LIMIT 1
                ]
                .Id;
                String blank;
                String missing;
                try {
                    ReceiptController.saveTemplate(perGift, ' ');
                } catch (AuraHandledException refused) {
                    blank = refused.getMessage();
                }
                try {
                    ReceiptController.activateTemplate(
                        FakeIds.of(Receipt_Template__c.SObjectType, 1)
                    );
                } catch (AuraHandledException refused) {
                    missing = refused.getMessage();
                }

                Assert.areEqual(
                    Label.Giving_Receipt_EmptyTemplate,
                    blank,
                    'An empty letter is refused'
                );
                Assert.areEqual(
                    Label.Giving_Receipt_TemplateNotFound,
                    missing,
                    'A letter that is not there is named'
                );
            }
        }
    }

    @IsTest
    static void theRunHistoryShowsTheLatestTenAndAStatementRunCanBeStarted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                List<Receipt_Run__c> runs = new List<Receipt_Run__c>();
                for (Integer i = 0; i < 12; i++) {
                    runs.add(
                        new Receipt_Run__c(
                            Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
                            Statement_Year__c = 2020 + (Math.mod(i, 5)),
                            Status__c = 'Completed',
                            Donors_Processed__c = 10,
                            Receipts_Issued__c = 9,
                            Errors__c = 1
                        )
                    );
                }
                insert runs;

                Test.startTest();
                List<ReceiptController.RunView> history = ReceiptController.getRuns();
                ReceiptController.RunView started = ReceiptController.startStatementRun(2025);
                ReceiptController.RunView defaulted = ReceiptController.startStatementRun(null);
                Test.stopTest();

                Assert.areEqual(10, history.size(), 'Only the latest ten are listed');
                Assert.areEqual(10, history[0].donorsProcessed, 'Counts are carried');
                Assert.areEqual(1, history[0].errors, 'Including errors');
                Assert.areEqual(2025, started.statementYear, 'The run is for the year asked');
                Assert.areEqual('Running', started.status, 'And is running');
                Assert.areEqual(
                    ReceiptController.getDefaultStatementYear(),
                    defaulted.statementYear,
                    'A run with no year takes the default year'
                );
                Assert.areEqual(0, started.receiptsIssued, 'Nothing is issued yet');
            }
        }
    }

    @IsTest
    static void aStatementRunNeedsThePermissionToIssue() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                ReceiptService.issuePermission = false;
                String message;
                try {
                    ReceiptController.startStatementRun(2025);
                } catch (AuraHandledException refused) {
                    message = refused.getMessage();
                }
                Assert.areEqual(Label.Giving_Receipt_NoPermission, message, 'Refused in words');
                Assert.areEqual(0, [SELECT COUNT() FROM Receipt_Run__c], 'No run was recorded');
            }
        }
    }
}
