/**
 * Tests for quick gift entry (G-03), written as David entering gifts at an event: a check
 * from a person, a gift from an organization or a person account, and the mistakes that
 * happen on a phone.
 */
@IsTest
private class QuickGiftEntryControllerTest {
    private static Fund__c makeFund() {
        Fund__c fund = new Fund__c(Name = 'Annual Fund', Active__c = true, Is_Default__c = true);
        insert fund;
        return fund;
    }

    private static Appeal__c makeAppeal() {
        Appeal__c appeal = new Appeal__c(Name = 'Spring Appeal', Active__c = true);
        insert appeal;
        return appeal;
    }

    private static Contact makeContact() {
        Contact donor = new Contact(FirstName = 'Maria', LastName = 'Alvarez');
        insert donor;
        return donor;
    }

    private static Account makeAccount() {
        Account donor = new Account(Name = 'Riverside Foundation');
        insert donor;
        return donor;
    }

    private static void setDefaults(String fundId, String appealId) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Default_Fund__c = fundId;
        settings.Default_Appeal__c = appealId;
        upsert settings;
        // Every writer of a settings object clears the settings cache after it writes. Saving
        // the fund and the appeal above has already read the settings once in this transaction,
        // so without this the controller is answered from the copy taken before the write.
        SettingsService.clearCaches();
    }

    private static QuickGiftEntryController.GiftInput baseInput() {
        QuickGiftEntryController.GiftInput input = new QuickGiftEntryController.GiftInput();
        input.amount = 50;
        input.giftDate = Date.today();
        input.giftType = 'Check';
        return input;
    }

    private static Map<String, String> messagesByField(
        List<QuickGiftEntryController.FieldError> errors
    ) {
        Map<String, String> byField = new Map<String, String>();
        for (QuickGiftEntryController.FieldError error : errors) {
            byField.put(error.field, error.message);
        }
        return byField;
    }

    @IsTest
    static void getDefaultsReturnsTodayTheTypesAndTheOrgDefaults() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c fund = makeFund();
            Appeal__c appeal = makeAppeal();
            setDefaults(fund.Id, appeal.Id);

            Test.startTest();
            QuickGiftEntryController.EntryDefaults defaults = QuickGiftEntryController.getDefaults();
            Test.stopTest();

            Assert.areEqual(Date.today(), defaults.giftDate, 'A new gift starts dated today.');
            Assert.areEqual(
                fund.Id,
                defaults.defaultFundId,
                'The default fund comes from settings.'
            );
            Assert.areEqual(
                'Annual Fund',
                defaults.defaultFundName,
                'The fund is named for the form.'
            );
            Assert.areEqual(
                appeal.Id,
                defaults.defaultAppealId,
                'The default appeal comes from settings.'
            );
            Assert.isFalse(defaults.giftTypes.isEmpty(), 'The gift types come from the picklist.');
            Assert.areEqual(
                OrgShapeDetector.detect().hasPersonAccounts,
                defaults.hasPersonAccounts,
                'The form is told whether people in this org are accounts.'
            );
        }
    }

    @IsTest
    static void getDefaultsIgnoresASettingThatNamesARecordThatIsGone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact notAFund = makeContact();
            setDefaults(notAFund.Id, null);

            Test.startTest();
            QuickGiftEntryController.EntryDefaults defaults = QuickGiftEntryController.getDefaults();
            Test.stopTest();

            Assert.isNull(
                defaults.defaultFundId,
                'A settings key naming the wrong kind of record is ignored.'
            );
            Assert.isNull(
                defaults.defaultAppealId,
                'An empty settings key leaves the appeal unset.'
            );
        }
    }

    @IsTest
    static void getDefaultsFallsBackToTheFundCarryingTheDefaultFlag() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c flagged = makeFund();
            setDefaults(null, null);

            Test.startTest();
            QuickGiftEntryController.EntryDefaults defaults = QuickGiftEntryController.getDefaults();
            Test.stopTest();

            Assert.areEqual(
                flagged.Id,
                defaults.defaultFundId,
                'With no settings key the form shows the fund the save will use.'
            );
        }
    }

    @IsTest
    static void savesAGiftFromAPersonWithTheFundThePersonChose() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c fund = makeFund();
            Appeal__c appeal = makeAppeal();
            Contact donor = makeContact();

            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorContactId = donor.Id;
            input.appealId = appeal.Id;
            input.fundId = fund.Id;
            input.paymentReference = '1042';

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.isTrue(result.success, 'The gift saved.');
            Assert.isNotNull(result.giftName, 'The saved gift is named so the person can find it.');
            Gift__c saved = [
                SELECT
                    Donor_Contact__c,
                    Amount__c,
                    Type__c,
                    Status__c,
                    Appeal__c,
                    Payment_Reference__c
                FROM Gift__c
                WHERE Id = :result.giftId
            ];
            Assert.areEqual(donor.Id, saved.Donor_Contact__c, 'The donor is the contact chosen.');
            Assert.areEqual(50, saved.Amount__c, 'The amount is what was typed.');
            Assert.areEqual('Check', saved.Type__c, 'The type is what was chosen.');
            Assert.areEqual('Received', saved.Status__c, 'A gift entered here has arrived.');
            Assert.areEqual(
                '1042',
                saved.Payment_Reference__c,
                'The check number is kept for reconciling.'
            );

            List<Gift_Allocation__c> allocations = [
                SELECT Fund__c, Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :result.giftId
            ];
            Assert.isFalse(
                result.fundNotApplied,
                'A gift that is not already split takes the fund the person chose.'
            );
            Assert.areEqual(1, allocations.size(), 'One gift, one allocation.');
            Assert.areEqual(
                fund.Id,
                allocations[0].Fund__c,
                'The allocation is to the fund chosen.'
            );
            Assert.areEqual(50, allocations[0].Amount__c, 'The allocation is the whole gift.');
        }
    }

    @IsTest
    static void savesAGiftWhoseDonorIsAnAccount() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c fund = makeFund();
            Account donor = makeAccount();

            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorAccountId = donor.Id;
            input.fundId = fund.Id;

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.isTrue(result.success, 'A gift from an account saves the same way.');
            Gift__c saved = [
                SELECT Donor_Account__c, Donor_Contact__c
                FROM Gift__c
                WHERE Id = :result.giftId
            ];
            Assert.areEqual(donor.Id, saved.Donor_Account__c, 'The donor is the account chosen.');
            Assert.isNull(saved.Donor_Contact__c, 'A gift has one donor, not two.');
        }
    }

    @IsTest
    static void leavesTheDefaultAllocationAloneWhenNobodyChoseAFund() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Fund__c fund = makeFund();
            Contact donor = makeContact();

            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorContactId = donor.Id;

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.isTrue(result.success, 'A gift with no fund chosen still saves.');
            List<Gift_Allocation__c> allocations = [
                SELECT Fund__c, Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :result.giftId
            ];
            Assert.areEqual(
                1,
                allocations.size(),
                'The gift keeps the one allocation the package gave it, and gains no second one.'
            );
            Assert.areEqual(
                fund.Id,
                allocations[0].Fund__c,
                'Which is to the default fund, because nobody chose another.'
            );
            Assert.areEqual(50, allocations[0].Amount__c, 'And it is the whole gift.');
        }
    }

    @IsTest
    static void asksForADonorWhenNoneWasChosen() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(
                baseInput()
            );
            Test.stopTest();

            Assert.isFalse(result.success, 'A gift with no donor is not saved.');
            Map<String, String> byField = messagesByField(result.fieldErrors);
            Assert.isTrue(byField.containsKey('donor'), 'The message names the donor field.');
            Assert.areEqual(
                Label.Giving_QuickGiftEntry_ErrorDonorRequired,
                byField.get('donor'),
                'The message is the one the admin guide quotes.'
            );
        }
    }

    @IsTest
    static void refusesTwoDonorsOnOneGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = makeContact();
            Account organization = makeAccount();
            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorContactId = person.Id;
            input.donorAccountId = organization.Id;

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.isFalse(result.success, 'A gift has one donor.');
            Assert.areEqual(
                Label.Giving_QuickGiftEntry_ErrorDonorBoth,
                messagesByField(result.fieldErrors).get('donor'),
                'The message says to choose one.'
            );
        }
    }

    @IsTest
    static void refusesAnAmountThatIsNotPositiveAndAMissingDateAndType() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact donor = makeContact();
            QuickGiftEntryController.GiftInput input = new QuickGiftEntryController.GiftInput();
            input.donorContactId = donor.Id;
            input.amount = -50;

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.isFalse(result.success, 'None of that is a gift yet.');
            Map<String, String> byField = messagesByField(result.fieldErrors);
            Assert.areEqual(
                Label.Giving_QuickGiftEntry_ErrorAmountRequired,
                byField.get('amount'),
                'A refund is entered from the original gift, not here.'
            );
            Assert.isTrue(byField.containsKey('giftDate'), 'The date is asked for.');
            Assert.isTrue(byField.containsKey('giftType'), 'How it arrived is asked for.');
        }
    }

    @IsTest
    static void refusesATypeThatIsNotOnTheList() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact donor = makeContact();
            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorContactId = donor.Id;
            input.giftType = 'Cryptocurrency';

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.areEqual(
                Label.Giving_QuickGiftEntry_ErrorTypeInvalid,
                messagesByField(result.fieldErrors).get('giftType'),
                'Only the gift types the org uses are accepted.'
            );
        }
    }

    @IsTest
    static void refusesAFundOrAppealThatIsNotOne() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact donor = makeContact();
            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorContactId = donor.Id;
            input.fundId = donor.Id;
            input.appealId = donor.Id;

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Map<String, String> byField = messagesByField(result.fieldErrors);
            Assert.areEqual(
                Label.Giving_QuickGiftEntry_ErrorFundUnavailable,
                byField.get('fundId'),
                'A fund reference that is not a fund is refused.'
            );
            Assert.areEqual(
                Label.Giving_QuickGiftEntry_ErrorAppealUnavailable,
                byField.get('appealId'),
                'An appeal reference that is not an appeal is refused.'
            );
        }
    }

    /** An active pledge of this person with one payment of 50 due today. */
    private static Installment__c pledgePaymentDueToday(Id personId) {
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = personId,
            Amount__c = 50,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Expected_Total__c = 50,
            Installments_Planned__c = 1
        );
        insert pledge;
        delete [SELECT Id FROM Installment__c WHERE Commitment__c = :pledge.Id];
        Installment__c payment = new Installment__c(
            Commitment__c = pledge.Id,
            Sequence__c = 1,
            Due_Date__c = Date.today(),
            Expected_Amount__c = 50,
            Status__c = 'Scheduled'
        );
        insert payment;
        return payment;
    }

    @IsTest
    static void offersTheDonorsPaymentAndChoosesTheOnlyMatch() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact donor = makeContact();
            Installment__c payment = pledgePaymentDueToday(donor.Id);

            Test.startTest();
            GiftEntryPayments.Choices choices = QuickGiftEntryController.getPaymentChoices(
                donor.Id,
                null,
                Date.today(),
                50
            );
            Test.stopTest();

            Assert.areEqual(1, choices.choices.size(), 'The one payment owed is offered.');
            Assert.areEqual(
                payment.Id,
                choices.suggestedId,
                'It is the only match, so it is chosen.'
            );
        }
    }

    @IsTest
    static void savesAGiftThatPaysTheChosenPayment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            makeFund();
            Contact donor = makeContact();
            Installment__c payment = pledgePaymentDueToday(donor.Id);
            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorContactId = donor.Id;
            input.installmentId = payment.Id;

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.isTrue(
                result.success,
                'The gift saved: ' + result.fieldErrors + result.formError
            );
            Gift__c saved = [
                SELECT Installment__c, Commitment__c
                FROM Gift__c
                WHERE Id = :result.giftId
            ];
            Assert.areEqual(payment.Id, saved.Installment__c, 'The gift pays the payment chosen.');
            Assert.areEqual(
                payment.Commitment__c,
                saved.Commitment__c,
                'And belongs to its pledge.'
            );
            Assert.areEqual(
                'Paid',
                [SELECT Status__c FROM Installment__c WHERE Id = :payment.Id].Status__c,
                'The payment is paid by the gift triggers.'
            );
        }
    }

    @IsTest
    static void refusesAPaymentOfAnotherDonorAndSavesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            makeFund();
            Contact donor = makeContact();
            Contact someoneElse = new Contact(FirstName = 'Kim', LastName = 'Lee');
            insert someoneElse;
            Installment__c payment = pledgePaymentDueToday(someoneElse.Id);
            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorContactId = donor.Id;
            input.installmentId = payment.Id;

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.isFalse(result.success, 'Nothing saved.');
            Assert.areEqual(
                Label.Giving_GiftEntryPays_ErrorNotOpen,
                messagesByField(result.fieldErrors).get('installmentId'),
                'The message sits beside the payment list.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift was written.');
        }
    }

    @IsTest
    static void refusesAPaymentForAGiftOfGoods() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact donor = makeContact();
            Installment__c payment = pledgePaymentDueToday(donor.Id);
            QuickGiftEntryController.GiftInput input = baseInput();
            input.donorContactId = donor.Id;
            input.giftType = 'In-kind';
            input.inKindDescription = 'Two chairs';
            input.installmentId = payment.Id;

            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(input);
            Test.stopTest();

            Assert.areEqual(
                Label.Giving_GiftEntryPays_ErrorInKind,
                messagesByField(result.fieldErrors).get('installmentId'),
                'A gift of goods pays no pledge.'
            );
        }
    }

    @IsTest
    static void saysSoWhenNothingArrivedToSave() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            QuickGiftEntryController.SaveResult result = QuickGiftEntryController.saveGift(null);
            Test.stopTest();

            Assert.isFalse(result.success, 'Nothing was saved.');
            Assert.areEqual(
                Label.Giving_QuickGiftEntry_ErrorNoInput,
                result.formError,
                'The person is told to enter the gift again.'
            );
        }
    }
}
