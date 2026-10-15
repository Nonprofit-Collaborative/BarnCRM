/**
 * One inbound gift on its way through the service (feature X-03): what the caller asked for,
 * what its references resolved to, and, once known, its answer.
 *
 * `validate` is everything that can be checked without a query, so a malformed gift is answered
 * before the service spends one. `toGift` is the `Gift__c` it becomes: Received, dated today
 * when the caller gave no date, with Giving's own triggers left to do the rest (ADR-0045).
 */
public with sharing class InboundGiftRequest {
    @TestVisible
    private static final Integer MAX_EXTERNAL_ID = 100;
    @TestVisible
    private static final Integer MAX_PAYMENT_REFERENCE = 255;
    private static final String STATUS_RECEIVED = 'Received';
    private static final String TYPE_IN_KIND = 'In-kind';
    private static Map<String, String> paymentMethodsByKey;

    public InboundGift request;
    /** The external id as stored: trimmed. */
    public String externalId;
    /** The external id as matched: lower cased, because its unique index ignores case (R-G7). */
    public String key;
    public String paymentMethod;
    public Id donorContactId;
    public Id donorAccountId;
    public Id fundId;
    public Id appealId;
    public Id giftId;
    public Id recordedGiftId;
    public Decimal recordedAmount;
    public InboundGiftResult result;

    public InboundGiftRequest(InboundGift request) {
        this.request = request;
    }

    /** Sets `result` to the first problem found, and leaves it empty when there is none. */
    public void validate() {
        result = firstProblem();
    }

    public Gift__c toGift() {
        return new Gift__c(
            External_Id__c = externalId,
            Amount__c = request.amount,
            Gift_Date__c = request.giftDate == null ? Date.today() : request.giftDate,
            Type__c = paymentMethod,
            Status__c = STATUS_RECEIVED,
            Payment_Reference__c = String.isBlank(request.paymentReference)
                ? null
                : request.paymentReference.trim(),
            Donor_Contact__c = donorContactId,
            Donor_Account__c = donorAccountId,
            Appeal__c = appealId
        );
    }

    /** The identifier a caller sent, or null when it is not one. */
    public static Id asId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception malformed) {
            return null;
        }
    }

    private InboundGiftResult firstProblem() {
        if (request == null) {
            return invalid(required('externalId'));
        }
        externalId = request.externalId == null ? '' : request.externalId.trim();
        if (String.isBlank(externalId)) {
            return invalid(required('externalId'));
        }
        if (externalId.length() > MAX_EXTERNAL_ID) {
            return invalid(tooLong('externalId', MAX_EXTERNAL_ID));
        }
        key = externalId.toLowerCase();

        if (request.amount == null) {
            return invalid(required('amount'));
        }
        if (
            request.amount <= 0 ||
            request.amount != request.amount.setScale(2, System.RoundingMode.DOWN)
        ) {
            return invalid(Label.Mirror_InboundGift_ErrorAmount);
        }

        if (String.isBlank(request.paymentMethod)) {
            return invalid(required('paymentMethod'));
        }
        Map<String, String> methods = paymentMethods();
        paymentMethod = methods.get(request.paymentMethod.trim().toLowerCase());
        if (paymentMethod == null) {
            return invalid(
                String.format(
                    Label.Mirror_InboundGift_ErrorPaymentMethod,
                    new List<String>{ String.join(methods.values(), ', ') }
                )
            );
        }

        if (
            request.paymentReference != null &&
            request.paymentReference.trim().length() > MAX_PAYMENT_REFERENCE
        ) {
            return invalid(tooLong('paymentReference', MAX_PAYMENT_REFERENCE));
        }

        Boolean byId = String.isNotBlank(request.donorId);
        Boolean byEmail = String.isNotBlank(request.donorEmail);
        if (byId && byEmail) {
            return invalid(Label.Mirror_InboundGift_ErrorDonorBoth);
        }
        if (!byId && !byEmail) {
            return invalid(Label.Mirror_InboundGift_ErrorDonorMissing);
        }
        if (String.isNotBlank(request.fundId) && String.isNotBlank(request.fundCode)) {
            return invalid(Label.Mirror_InboundGift_ErrorFundBoth);
        }
        return null;
    }

    /**
     * The payment methods a gift from outside may carry, by lower cased value: every active gift
     * type except In-kind, because goods have no amount (R-G12, ADR-0030).
     */
    private static Map<String, String> paymentMethods() {
        if (paymentMethodsByKey == null) {
            paymentMethodsByKey = new Map<String, String>();
            for (Schema.PicklistEntry entry : Gift__c.Type__c.getDescribe().getPicklistValues()) {
                if (entry.isActive() && entry.getValue() != TYPE_IN_KIND) {
                    paymentMethodsByKey.put(entry.getValue().toLowerCase(), entry.getValue());
                }
            }
        }
        return paymentMethodsByKey;
    }

    private static InboundGiftResult invalid(String message) {
        return InboundGiftResult.rejected(InboundGiftResult.ERROR_INVALID_FIELD, message);
    }

    private static String required(String field) {
        return String.format(Label.Mirror_InboundGift_ErrorRequired, new List<String>{ field });
    }

    private static String tooLong(String field, Integer limitLength) {
        return String.format(
            Label.Mirror_InboundGift_ErrorTooLong,
            new List<String>{ field, String.valueOf(limitLength) }
        );
    }
}
