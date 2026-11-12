/**
 * Projects' listener on the payment seam (PM-10, R-PM22; ADR-0201 `0201-payments-module.md`,
 * decision 8; ADR-NEXT `NEXT-projects-psa.md` decision 6). BarnCRM Payments builds it by the name
 * stored on each payment Send Payment Link started and tells it once per run about every changed
 * payment (`paymentsChanged`), or one at a time (`paymentChanged`) when the bulk call failed; the
 * work is `ProjectInvoicePayments.apply`.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because another package
 * builds it by name (ADR-0017). Its name is permanent once released.
 */
@NamespaceAccessible
public with sharing class ProjectInvoicePaymentListener implements Callable {
	@NamespaceAccessible
	public ProjectInvoicePaymentListener() {
		// Built by name by BarnCRM Payments, so it needs a public constructor.
	}

	public Object call(String action, Map<String, Object> args) {
		if (args == null) {
			return null;
		}
		if (action == 'paymentsChanged' && args.get('payments') instanceof List<Object>) {
			List<Map<String, Object>> payments = new List<Map<String, Object>>();
			for (Object payment : (List<Object>) args.get('payments')) {
				payments.add((Map<String, Object>) payment);
			}
			ProjectInvoicePayments.apply(payments);
			return true;
		}
		if (action == 'paymentChanged') {
			ProjectInvoicePayments.apply(new List<Map<String, Object>>{ args });
		}
		return null;
	}
}
