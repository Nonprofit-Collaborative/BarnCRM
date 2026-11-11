/**
 * The payment seam (ADR-NEXT `NEXT-payments-module.md`, decision 8; the module README, "The
 * Payment Seam"). A module that charges builds this class by name
 * (`NamespaceUtil.build('PaymentsApi', Callable.class, context)`) and calls:
 *
 *   startCheckout  { amount, description, successUrl, cancelUrl, currency?, processor?,
 *                    payerName?, payerEmail?, personId?, sourceRecordId?, listener? }
 *                  returns { paymentId, checkoutUrl, status, reference }
 *   getPayment     { paymentId } returns the payment map, or null
 *   isReady        { processor? } returns true when that processor's keys are entered
 *
 * Action names and keys are permanent once released; new optional keys may be added.
 */
@NamespaceAccessible
public with sharing class PaymentsApi implements Callable {
	/** A request Payments refuses, with a message fit to show the person. */
	public class PaymentException extends Exception {
	}

	@NamespaceAccessible
	public PaymentsApi() {
		// Built by name by the modules that charge, so it needs a public constructor.
	}

	public Object call(String action, Map<String, Object> args) {
		Map<String, Object> given = args == null ? new Map<String, Object>() : args;
		switch on action {
			when 'startCheckout' {
				Payment__c payment = PaymentService.startCheckout(given);
				return new Map<String, Object>{
					'paymentId' => payment.Id,
					'checkoutUrl' => payment.Checkout_Url__c,
					'status' => payment.Status__c,
					'reference' => payment.Reference__c
				};
			}
			when 'getPayment' {
				Id paymentId = given.get('paymentId') instanceof Id
					? (Id) given.get('paymentId')
					: null;
				if (paymentId == null && given.get('paymentId') instanceof String) {
					paymentId = Id.valueOf((String) given.get('paymentId'));
				}
				List<Payment__c> found = [
					SELECT
						Id,
						Status__c,
						Amount__c,
						Amount_Refunded__c,
						Source_Record_Id__c,
						Person__c,
						Currency_Code__c,
						Processor__c,
						Mode__c,
						Paid_At__c,
						Detail__c
					FROM Payment__c
					WHERE Id = :paymentId
					WITH USER_MODE
				];
				return found.isEmpty() ? null : PaymentService.toMap(found[0]);
			}
			when 'isReady' {
				Object processor = given.get('processor');
				return PaymentService.isReady(
					processor == null
						? PaymentService.defaultProcessor()
						: String.valueOf(processor)
				);
			}
			when else {
				throw new PaymentException(
					BarnHelp.text(
						'Payments',
						'Payments_Error_UnknownAction',
						new List<Object>{ action }
					)
				);
			}
		}
	}
}
