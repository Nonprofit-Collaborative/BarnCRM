/**
 * Tests for the gift batch grid's controller (G-17), run as David, who types the Tuesday mail.
 * The posting rules themselves are tested in `GiftBatchServiceTest`; this class covers what the
 * grid sends and what it is sent back.
 */
@IsTest
private class GiftBatchControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static User david() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
    }

    private static Gift_Batch__c batch(Decimal controlTotal) {
        Gift_Batch__c batch = new Gift_Batch__c(
            Description__c = 'Tuesday mail',
            Control_Total__c = controlTotal,
            Default_Payment_Method__c = 'Check'
        );
        insert batch;
        return batch;
    }

    private static GiftBatchController.Line typed(Id contactId, Decimal amount) {
        GiftBatchController.Line line = new GiftBatchController.Line();
        line.donorContactId = contactId;
        line.amount = amount;
        return line;
    }

    @IsTest
    static void eachLineIsOfferedItsDonorsPaymentsAndTheChoiceIsSaved() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User fundraiser = david();
            System.runAs(fundraiser) {
                Contact ana = new Contact(FirstName = 'Ana', LastName = 'Garcia');
                insert ana;
                Commitment__c pledge = new Commitment__c(
                    Type__c = 'Pledge',
                    Status__c = 'Active',
                    Donor_Contact__c = ana.Id,
                    Amount__c = 100,
                    Frequency__c = 'Monthly',
                    Start_Date__c = Date.today(),
                    Expected_Total__c = 300,
                    Installments_Planned__c = 3
                );
                insert pledge;
                Installment__c first = [
                    SELECT Id
                    FROM Installment__c
                    WHERE Commitment__c = :pledge.Id
                    ORDER BY Sequence__c
                    LIMIT 1
                ];
                Gift_Batch__c tuesday = batch(100);
                GiftBatchController.Line anas = typed(ana.Id, 100);
                anas.key = 'new-1';
                anas.giftDate = Date.today();
                GiftBatchController.Line nobodys = typed(null, 25);
                nobodys.key = 'new-2';

                Test.startTest();
                Map<String, GiftEntryPayments.Choices> byKey = new Map<String, GiftEntryPayments.Choices>();
                for (
                    GiftEntryPayments.Choices choices : GiftBatchController.getPaymentChoices(
                        tuesday.Id,
                        new List<GiftBatchController.Line>{ anas, nobodys }
                    )
                ) {
                    byKey.put(choices.key, choices);
                }
                anas.installmentId = first.Id;
                GiftBatchController.BatchView saved = GiftBatchController.saveLines(
                    tuesday.Id,
                    new List<GiftBatchController.Line>{ anas },
                    null
                );
                Test.stopTest();

                Assert.areEqual(3, byKey.get('new-1').choices.size(), 'Ana owes three payments.');
                Assert.areEqual(
                    first.Id,
                    byKey.get('new-1').suggestedId,
                    'The only match is chosen.'
                );
                Assert.isTrue(byKey.get('new-2').choices.isEmpty(), 'No donor, nothing owed.');
                Assert.areEqual(first.Id, saved.lines[0].installmentId, 'The choice is saved.');
            }

        }
    }

    @IsTest
    static void aNewBatchOpensEmptyWithItsDefaultsAndNoInKindMethod() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User fundraiser = david();
            System.runAs(fundraiser) {
                Gift_Batch__c tuesday = batch(100);

                Test.startTest();
                GiftBatchController.BatchView view = GiftBatchController.getBatch(tuesday.Id);
                Test.stopTest();

                Assert.isFalse(view.posted, 'A new batch is open.');
                Assert.areEqual(100, view.controlTotal, 'The control total is shown.');
                Assert.areEqual(0, view.enteredTotal, 'Nothing has been typed.');
                Assert.isTrue(view.lines.isEmpty(), 'No lines yet.');
                Assert.isFalse(
                    view.paymentMethods.isEmpty(),
                    'The methods come from the picklist.'
                );
                for (GiftBatchController.Option option : view.paymentMethods) {
                    Assert.areNotEqual(
                        'In-kind',
                        option.value,
                        'Goods are not entered in a deposit.'
                    );
                }
            }

        }
    }

    @IsTest
    static void savingTheGridAddsChangesAndRemovesLinesInOneGo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User fundraiser = david();
            System.runAs(fundraiser) {
                Contact ana = new Contact(FirstName = 'Ana', LastName = 'Garcia');
                insert ana;
                Gift_Batch__c tuesday = batch(150);
                GiftBatchController.BatchView first = GiftBatchController.saveLines(
                    tuesday.Id,
                    new List<GiftBatchController.Line>{ typed(ana.Id, 100), typed(null, 25) },
                    null
                );
                Assert.areEqual(2, first.lines.size(), 'Both lines were saved.');
                Assert.areEqual(125, first.enteredTotal, 'The total is the server sum.');

                GiftBatchController.Line changed = first.lines[0];
                changed.amount = 150;
                changed.paymentMethod = 'Not a method';

                Test.startTest();
                GiftBatchController.BatchView second = GiftBatchController.saveLines(
                    tuesday.Id,
                    new List<GiftBatchController.Line>{ changed },
                    new List<String>{ first.lines[1].id, 'not an id' }
                );
                Test.stopTest();

                Assert.areEqual(1, second.lines.size(), 'The removed line is gone.');
                Assert.areEqual(150, second.enteredTotal, 'The change was saved.');
                Assert.isNull(second.lines[0].paymentMethod, 'An unknown method is not stored.');
            }

        }
    }

    @IsTest
    static void aLineFromAnotherBatchIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User fundraiser = david();
            System.runAs(fundraiser) {
                Gift_Batch__c tuesday = batch(100);
                Gift_Batch__c wednesday = batch(100);
                GiftBatchController.BatchView other = GiftBatchController.saveLines(
                    wednesday.Id,
                    new List<GiftBatchController.Line>{ typed(null, 10) },
                    null
                );

                Test.startTest();
                try {
                    GiftBatchController.saveLines(tuesday.Id, other.lines, null);
                    Assert.fail('A line of another batch must not be saved through this one.');
                } catch (AuraHandledException e) {
                    Assert.areEqual(
                        Label.Giving_GiftBatch_ErrorLineMissing,
                        e.getMessage(),
                        'Why.'
                    );
                }
                Test.stopTest();
            }

        }
    }

    @IsTest
    static void postingReportsTheResultAndThePostedBatchCannotBeTypedInto() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c general = new Fund__c(Name = 'General', Active__c = true, Is_Default__c = true);
            insert general;
            User fundraiser = david();
            System.runAs(fundraiser) {
                Contact ana = new Contact(FirstName = 'Ana', LastName = 'Garcia');
                insert ana;
                Gift_Batch__c tuesday = batch(100);
                GiftBatchController.saveLines(
                    tuesday.Id,
                    new List<GiftBatchController.Line>{ typed(ana.Id, 60), typed(null, 40) },
                    null
                );

                GiftBatchController.PostResult refused = GiftBatchController.postBatch(tuesday.Id);
                Assert.isFalse(refused.success, 'The line with no donor stops the post.');
                Assert.areEqual(1, refused.lineErrors.size(), 'One line is named.');
                Assert.areEqual(2, refused.lineErrors[0].lineNumber, 'It is the second line.');

                GiftBatchController.BatchView view = GiftBatchController.getBatch(tuesday.Id);
                view.lines[1].donorContactId = ana.Id;
                GiftBatchController.saveLines(tuesday.Id, view.lines, null);

                Test.startTest();
                GiftBatchController.PostResult posted = GiftBatchController.postBatch(tuesday.Id);
                Test.stopTest();

                Assert.isTrue(posted.success, 'The finished batch posts: ' + posted.formError);
                Assert.areEqual(2, posted.giftCount, 'Two gifts.');
                GiftBatchController.BatchView after = GiftBatchController.getBatch(tuesday.Id);
                Assert.isTrue(after.posted, 'The batch shows as posted.');
                Assert.isNotNull(after.lines[0].giftName, 'Each line names the gift it became.');
                try {
                    GiftBatchController.saveLines(tuesday.Id, after.lines, null);
                    Assert.fail('A posted batch cannot be typed into.');
                } catch (AuraHandledException e) {
                    Assert.areEqual(
                        Label.Giving_GiftBatch_ErrorEditAfterPost,
                        e.getMessage(),
                        'Why.'
                    );
                }
            }

        }
    }

    @IsTest
    static void someoneWhoMayOnlyReadIsToldSoAndChangesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c general = new Fund__c(Name = 'General', Active__c = true, Is_Default__c = true);
            insert general;
            User fundraiser = david();
            User treasurer = TestDataFactory.createUser(
                'Jen',
                new List<String>{ 'BarnCRM_Read_Only', 'Giving_Read_Only' }
            );
            Gift_Batch__c tuesday;
            System.runAs(fundraiser) {
                Contact ana = new Contact(FirstName = 'Ana', LastName = 'Garcia');
                insert ana;
                tuesday = batch(100);
                GiftBatchController.saveLines(
                    tuesday.Id,
                    new List<GiftBatchController.Line>{ typed(ana.Id, 100) },
                    null
                );
                insert new Gift_Batch__Share(
                    ParentId = tuesday.Id,
                    UserOrGroupId = treasurer.Id,
                    AccessLevel = 'Read'
                );
            }

            System.runAs(treasurer) {
                Test.startTest();
                GiftBatchController.BatchView seen = GiftBatchController.getBatch(tuesday.Id);
                try {
                    GiftBatchController.saveLines(tuesday.Id, seen.lines, null);
                    Assert.fail('A reader cannot save lines.');
                } catch (AuraHandledException e) {
                    Assert.areEqual(Label.Giving_GiftBatch_ErrorNoAccess, e.getMessage(), 'Why.');
                }
                GiftBatchController.PostResult refused = GiftBatchController.postBatch(tuesday.Id);
                Test.stopTest();

                Assert.isFalse(seen.canEdit, 'The grid is told to offer no buttons.');
                Assert.areEqual(1, seen.lines.size(), 'The reader still sees the lines.');
                Assert.isFalse(refused.success, 'A reader cannot post.');
                Assert.areEqual(Label.Giving_GiftBatch_ErrorNoAccess, refused.formError, 'Why.');
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'Nothing was posted.');
        }
    }

    @IsTest
    static void aBatchThatIsNotThereSaysSo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift_Batch__c gone = batch(1);
            delete gone;

            Test.startTest();
            try {
                GiftBatchController.getBatch(gone.Id);
                Assert.fail('A deleted batch cannot be opened.');
            } catch (AuraHandledException e) {
                Assert.areEqual(Label.Giving_GiftBatch_ErrorBatchMissing, e.getMessage(), 'Why.');
            }
            Test.stopTest();
        }
    }
}
