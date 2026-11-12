/**
 * The seam a module's public page uses to take a payment when its form is sent (ADR-NEXT
 * `NEXT-online-donation-pages.md`, decision 2). A `PublicPageExtension` may also implement this;
 * `PublicPageExtensions.startCheckout` finds it for the record's type and the host (BarnCRM
 * Forms) asks it before storing anything, so a module's payment callout comes before any write.
 *
 * Core names no payment: the module decides whether the record charges and asks BarnCRM
 * Payments by name. Called for a Site guest user.
 */
@NamespaceAccessible
public interface PublicCheckoutExtension {
	/**
	 * Starts a hosted checkout for answers sent from a record's public page.
	 *
	 * @param recordId the record whose page the form was sent from
	 * @param answers the counted answers, by field key
	 * @param returnUrl the https address of the record's public page, where the payer returns
	 * @return `{ paymentId, checkoutUrl }`, or null when this record takes no payment
	 */
	Map<String, Object> startCheckout(Id recordId, Map<String, Object> answers, String returnUrl);
}
