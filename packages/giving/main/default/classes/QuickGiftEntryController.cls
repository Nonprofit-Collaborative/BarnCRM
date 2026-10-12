/**
 * Quick gift entry (G-03).
 *
 * Serves the `quickGiftEntry` component: the defaults a new gift starts from, and the save
 * of one gift with at most one allocation. Everything a gift needs beyond what this form
 * collects (the derived household, the default allocation, the auto-number name) is the
 * Giving domain's work, so this class stays a thin, validating entry point.
 *
 * Errors the person can act on are returned in the typed result and rendered beside the
 * field that caused them. Anything unexpected is logged to the Error Log and reported as
 * one plain sentence, because the person entering gifts at an event cannot act on a stack
 * trace (plan Section 2.3).
 */
public with sharing class QuickGiftEntryController {
    private static final String STATUS_RECEIVED = 'Received';
    private static final String TYPE_IN_KIND = 'In-kind';
    private static final String CONTEXT = 'QuickGiftEntryController';

    /**
     * The values a new gift starts from: today's date, the org's default fund and appeal,
     * the gift types, and whether people in this org are accounts rather than contacts.
     */
    @AuraEnabled(cacheable=true)
    public static EntryDefaults getDefaults() {
        try {
            EntryDefaults defaults = new EntryDefaults();
            defaults.giftDate = Date.today();
            defaults.giftTypes = giftTypeOptions();
            defaults.hasPersonAccounts = OrgShapeDetector.detect().hasPersonAccounts;
            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            applyDefaultFund(defaults, settings);
            applyDefaultAppeal(defaults, settings);
            return defaults;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getDefaults');
            throw asAuraException(Label.Giving_QuickGiftEntry_ErrorLoadDefaults);
        }
    }

    /**
     * Saves one gift and, when a fund was chosen, points the gift's single allocation at it.
     * Returns a result the component can render: the saved gift's name and id, or the
     * errors that stopped it.
     */
    @AuraEnabled
    public static SaveResult saveGift(GiftInput input) {
        SaveResult result = new SaveResult();
        if (input == null) {
            result.formError = Label.Giving_QuickGiftEntry_ErrorNoInput;
            return result;
        }
        result.fieldErrors = input.validate();
        if (!result.fieldErrors.isEmpty()) {
            return result;
        }
        try {
            Gift__c gift = input.toGift();
            Database.insert(gift, true, AccessLevel.USER_MODE);
            Boolean applyChosenFundWasApplied = applyChosenFund(
                gift,
                asId(input.fundId, Fund__c.SObjectType)
            );
            result.success = true;
            result.giftId = gift.Id;
            result.giftName = nameOf(gift.Id);
            result.fundNotApplied = !applyChosenFundWasApplied;
            return result;
        } catch (DmlException e) {
            ErrorLogger.log(e, CONTEXT + '.saveGift');
            result.formError = e.getNumDml() > 0
                ? e.getDmlMessage(0)
                : Label.Giving_QuickGiftEntry_ErrorUnexpected;
            return result;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.saveGift');
            result.formError = Label.Giving_QuickGiftEntry_ErrorUnexpected;
            return result;
        }
    }

    /**
     * The gift is inserted first, so the Giving domain has already given it its default
     * allocation. When the person chose a fund, that one allocation is pointed at their
     * choice rather than a second one being added, so the allocations still total the
     * gift (canonical model R-GA1).
     *
     * Returns false when the choice could not be applied, which happens only when the gift
     * already carries a split across several funds. The gift is saved either way, and the
     * component says so rather than reporting a designation the gift does not have.
     */
    private static Boolean applyChosenFund(Gift__c gift, Id fundId) {
        if (fundId == null) {
            return true;
        }
        return !GiftService.applyChosenFunds(
                new List<Gift__c>{ gift },
                new Map<Id, Id>{ gift.Id => fundId }
            )
            .contains(gift.Id);
    }

    private static String nameOf(Id giftId) {
        List<Gift__c> saved = GiftSelector.selectById(new Set<Id>{ giftId });
        return saved.isEmpty() ? null : saved[0].Name;
    }

    /**
     * The form shows the fund the gift will actually land in. Where the settings key names
     * no usable fund, the save falls back to the fund carrying the default flag (R-F4,
     * R-GA2), so the form asks the domain the same question rather than showing an empty
     * Fund box and then designating the gift somewhere the person never saw.
     */
    private static void applyDefaultFund(EntryDefaults defaults, Giving_Settings__c settings) {
        Id fundId = asId(settings.Default_Fund__c, Fund__c.SObjectType);
        if (fundId == null) {
            fundId = GiftService.resolveDefaultFundId();
        }
        if (fundId == null) {
            return;
        }
        for (Fund__c fund : FundSelector.selectById(new Set<Id>{ fundId })) {
            if (fund.Active__c) {
                defaults.defaultFundId = fund.Id;
                defaults.defaultFundName = fund.Name;
            }
        }
    }

    private static void applyDefaultAppeal(EntryDefaults defaults, Giving_Settings__c settings) {
        Id appealId = asId(settings.Default_Appeal__c, Appeal__c.SObjectType);
        if (appealId == null) {
            return;
        }
        for (Appeal__c appeal : AppealSelector.selectById(new Set<Id>{ appealId })) {
            if (appeal.Active__c) {
                defaults.defaultAppealId = appeal.Id;
                defaults.defaultAppealName = appeal.Name;
            }
        }
    }

    /**
     * A settings key holds an identifier as text (ADR-0014), and the record it names can
     * have been deleted since. Anything that is not a live identifier of the expected kind
     * is treated as no default rather than as an error, so a stale key never blocks entry.
     */
    private static Id asId(String value, Schema.SObjectType expected) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id parsed = Id.valueOf(value.trim());
            return parsed.getSobjectType() == expected ? parsed : null;
        } catch (System.StringException e) {
            return null;
        }
    }

    private static List<PicklistOption> giftTypeOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : Gift__c.Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static Set<String> giftTypeValues() {
        Set<String> values = new Set<String>();
        for (PicklistOption option : giftTypeOptions()) {
            values.add(option.value);
        }
        return values;
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    /** One choice in the "How it arrived" list. */
    public class PicklistOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** What a new gift starts from. */
    public class EntryDefaults {
        @AuraEnabled
        public Date giftDate;
        @AuraEnabled
        public Boolean hasPersonAccounts = false;
        @AuraEnabled
        public String defaultFundId;
        @AuraEnabled
        public String defaultFundName;
        @AuraEnabled
        public String defaultAppealId;
        @AuraEnabled
        public String defaultAppealName;
        @AuraEnabled
        public List<PicklistOption> giftTypes = new List<PicklistOption>();
    }

    /** One message the component shows beside one field. */
    public class FieldError {
        @AuraEnabled
        public String field;
        @AuraEnabled
        public String message;

        public FieldError(String field, String message) {
            this.field = field;
            this.message = message;
        }
    }

    /** What came of a save. */
    public class SaveResult {
        @AuraEnabled
        public Boolean success = false;
        @AuraEnabled
        public String giftId;
        @AuraEnabled
        public String giftName;
        @AuraEnabled
        public String formError;
        @AuraEnabled
        public Boolean fundNotApplied = false;
        @AuraEnabled
        public List<FieldError> fieldErrors = new List<FieldError>();
    }

    /**
     * The gift the person typed. Every value arrives as it was entered and is validated
     * here, so no other class has to trust the browser.
     */
    public class GiftInput {
        @AuraEnabled
        public String donorContactId;
        @AuraEnabled
        public String donorAccountId;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Date giftDate;
        @AuraEnabled
        public String giftType;
        @AuraEnabled
        public String appealId;
        @AuraEnabled
        public String fundId;
        @AuraEnabled
        public String paymentReference;
        @AuraEnabled
        public String inKindDescription;
        @AuraEnabled
        public Decimal fairMarketValue;

        public List<FieldError> validate() {
            List<FieldError> errors = new List<FieldError>();
            validateDonor(errors);
            validateAmountOrGoods(errors);
            if (this.giftDate == null) {
                errors.add(
                    new FieldError('giftDate', Label.Giving_QuickGiftEntry_ErrorDateRequired)
                );
            }
            validateType(errors);
            if (
                String.isNotBlank(this.appealId) &&
                asId(this.appealId, Appeal__c.SObjectType) == null
            ) {
                errors.add(
                    new FieldError('appealId', Label.Giving_QuickGiftEntry_ErrorAppealUnavailable)
                );
            }
            if (String.isNotBlank(this.fundId) && asId(this.fundId, Fund__c.SObjectType) == null) {
                errors.add(
                    new FieldError('fundId', Label.Giving_QuickGiftEntry_ErrorFundUnavailable)
                );
            }
            return errors;
        }

        /**
         * A gift is money or goods, never both (R-G12, ADR-0030). A gift of money needs an amount
         * above zero; a gift of goods has no amount at all and needs the description that its
         * receipt will print. The fair market value is optional, because a donor can hand over a
         * carload of furniture before anybody has put a figure on it, but it is never negative.
         */
        private void validateAmountOrGoods(List<FieldError> errors) {
            if (isInKind()) {
                if (String.isBlank(this.inKindDescription)) {
                    errors.add(
                        new FieldError(
                            'inKindDescription',
                            Label.Giving_QuickGiftEntry_ErrorInKindDescriptionRequired
                        )
                    );
                }
                if (this.fairMarketValue != null && this.fairMarketValue < 0) {
                    errors.add(
                        new FieldError(
                            'fairMarketValue',
                            Label.Giving_QuickGiftEntry_ErrorFairMarketValueNegative
                        )
                    );
                }
                return;
            }
            if (this.amount == null || this.amount <= 0) {
                errors.add(
                    new FieldError('amount', Label.Giving_QuickGiftEntry_ErrorAmountRequired)
                );
            }
        }

        @TestVisible
        private Boolean isInKind() {
            return TYPE_IN_KIND.equalsIgnoreCase(this.giftType);
        }

        private void validateDonor(List<FieldError> errors) {
            Boolean hasContact =
                String.isNotBlank(this.donorContactId) &&
                asId(this.donorContactId, Contact.SObjectType) != null;
            Boolean hasAccount =
                String.isNotBlank(this.donorAccountId) &&
                asId(this.donorAccountId, Account.SObjectType) != null;
            if (hasContact && hasAccount) {
                errors.add(new FieldError('donor', Label.Giving_QuickGiftEntry_ErrorDonorBoth));
            } else if (!hasContact && !hasAccount) {
                errors.add(new FieldError('donor', Label.Giving_QuickGiftEntry_ErrorDonorRequired));
            }
        }

        private void validateType(List<FieldError> errors) {
            if (String.isBlank(this.giftType)) {
                errors.add(
                    new FieldError('giftType', Label.Giving_QuickGiftEntry_ErrorTypeRequired)
                );
                return;
            }
            if (!giftTypeValues().contains(this.giftType)) {
                errors.add(
                    new FieldError('giftType', Label.Giving_QuickGiftEntry_ErrorTypeInvalid)
                );
            }
        }

        /**
         * An in-kind gift is saved with an amount of zero and its worth on Fair Market Value, and
         * a gift that is not in-kind carries neither of the in-kind attributes, whatever the
         * browser sent: a description left behind by somebody switching the type back and forth
         * would otherwise read later as a gift of goods (R-G12).
         */
        public Gift__c toGift() {
            Boolean inKind = isInKind();
            return new Gift__c(
                Donor_Contact__c = asId(this.donorContactId, Contact.SObjectType),
                Donor_Account__c = asId(this.donorAccountId, Account.SObjectType),
                Gift_Date__c = this.giftDate,
                Amount__c = inKind ? 0 : this.amount,
                Type__c = this.giftType,
                Status__c = STATUS_RECEIVED,
                Appeal__c = asId(this.appealId, Appeal__c.SObjectType),
                Payment_Reference__c = this.paymentReference,
                In_Kind_Description__c = inKind ? this.inKindDescription : null,
                Fair_Market_Value__c = inKind ? this.fairMarketValue : null
            );
        }
    }
}
