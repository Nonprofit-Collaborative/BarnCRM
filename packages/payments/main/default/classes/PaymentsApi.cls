/**
 * The payment seam (ADR-NEXT `NEXT-payments-module.md`, decision 8; the module README, "The
 * Payment Seam"). A module that charges builds this class by name
 * (`NamespaceUtil.build('PaymentsApi', Callable.class, context)`) and calls:
 *
 *   startCheckout  { amount, description, successUrl, cancelUrl, currency?, processor?,
 *                    payerName?, payerEmail?, personId?, sourceRecordId?, listener?, detail? }
 *                  returns { paymentId, checkoutUrl, status, reference }
 *   getPayment     { paymentId } returns the payment map, or null
 *   isReady        { processor? } returns true when that processor's keys are entered
 *   countRecent    { sourceRecordId, minutes?, status? } returns how many payments for that
 *                  record were started in the last minutes (default 60), of that status if given
 *
 * A listener named on a payment is told `paymentsChanged { payments: [payment map, ...] }`
 * once per run and answers true when it handled them; otherwise it is told
 * `paymentChanged { payment map }` once per payment.
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
			when 'countRecent' {
				// A count only, in system mode: a public page's guest checks it before a checkout.
				Integer minutes = given.get('minutes') instanceof Integer
					? (Integer) given.get('minutes')
					: 60;
				String source = String.valueOf(given.get('sourceRecordId')).left(18);
				Set<String> statuses = given.get('status') == null
					? new Set<String>{
							PaymentService.PENDING,
							PaymentService.PAID,
							PaymentService.FAILED,
							PaymentService.REFUNDED,
							PaymentService.CANCELLED
					  }
					: new Set<String>{ String.valueOf(given.get('status')) };
				Datetime since = Datetime.now().addMinutes(-minutes);
				return [
					SELECT COUNT()
					FROM Payment__c
					WHERE
						Source_Record_Id__c = :source
						AND CreatedDate >= :since
						AND Status__c IN :statuses
					WITH SYSTEM_MODE
				];
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
