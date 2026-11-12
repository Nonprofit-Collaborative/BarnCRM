/**
 * Events' listener on the payment seam (EV-20; ADR-NEXT `NEXT-payments-module.md`, decision 8;
 * ADR-NEXT `NEXT-events-paid-registration-proposals-ratings.md`, decision 5). BarnCRM Payments
 * builds it by the name stored on each payment Events started and calls `paymentChanged` when the
 * payment's status or refunded amount changes; the work is `EventPayments.apply`.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because another package
 * builds it by name (ADR-0017). Its name is permanent once released.
 */
@NamespaceAccessible
public with sharing class EventPaymentListener implements Callable {
	@NamespaceAccessible
	public EventPaymentListener() {
		// Built by name by BarnCRM Payments, so it needs a public constructor.
	}

	public Object call(String action, Map<String, Object> args) {
		if (action == 'paymentChanged' && args != null) {
			EventPayments.apply(args);
		}
		return null;
	}
}
