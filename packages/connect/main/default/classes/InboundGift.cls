/**
 * One gift as another system describes it: the body of the inbound gift API and the input of
 * the Record Inbound Gift Flow action (feature X-03). One class carries both, so the two ways in
 * cannot drift apart in what they accept.
 *
 * `global` because a Flow in a subscriber org builds one and the REST body is read into it.
 * Every variable here is permanent once the package is managed (ADR-0051): a new optional
 * variable may be added, none may be removed or renamed. The rules applied to these values are
 * in `InboundGiftService` and the API reference, `docs/api/inbound-gift-api.md`.
 *
 * Each description is written for an administrator and for a customer's own AI agent choosing
 * values (see `InboundGiftAction`): it states whether the input is required, its exact format,
 * and what the action does with it. Keep each under 255 characters.
 */
global with sharing class InboundGift {
    @InvocableVariable(
        label='External Id'
        description='Required. The gift\'s unique identifier in the system that sent it, up to 100 characters, matched ignoring case. Prefix it with the system\'s name, for example stripe:ch_123. Send the same value only to resend the same gift.'
        required=true
    )
    global String externalId;

    @InvocableVariable(
        label='Amount'
        description='Required. The amount received: greater than zero, at most two decimal places. A refund or a negative amount is refused.'
        required=true
    )
    global Decimal amount;

    @InvocableVariable(
        label='Payment Method'
        description='Required. How the gift was paid: Cash, Check, Card, ACH, Stock, Grant or Other, not case sensitive. Gifts of goods (In-kind) are refused.'
        required=true
    )
    global String paymentMethod;

    @InvocableVariable(
        label='Gift Date'
        description='Optional. The day the money arrived. Today when left empty.'
    )
    global Date giftDate;

    @InvocableVariable(
        label='Payment Reference'
        description='Optional. A check number, transaction id or deposit reference, up to 255 characters.'
    )
    global String paymentReference;

    @InvocableVariable(
        label='Donor Id'
        description='The Salesforce record id of the person or organization who gave. Send exactly one of Donor Id and Donor Email; an organization can be named only by id. A donor is never created.'
    )
    global String donorId;

    @InvocableVariable(
        label='Donor Email'
        description='The email address of the person who gave, matched exactly, ignoring case. Send exactly one of Donor Id and Donor Email. A donor is never created: an unknown address is refused.'
    )
    global String donorEmail;

    @InvocableVariable(
        label='Fund Accounting Code'
        description='Optional. The accounting code of the active fund the gift is for. Send this or Fund Id, not both. With neither, the gift goes to the default fund.'
    )
    global String fundCode;

    @InvocableVariable(
        label='Fund Id'
        description='Optional. The record id of the active fund the gift is for, instead of Fund Accounting Code. With neither, the gift goes to the default fund.'
    )
    global String fundId;

    @InvocableVariable(
        label='Appeal Id'
        description='Optional. The record id of the appeal the gift responds to.'
    )
    global String appealId;

    /** Flow, the REST endpoint and subscriber Apex each build a gift field by field. */
    global InboundGift() {
    }
}
