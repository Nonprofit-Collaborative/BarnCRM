/**
 * The shipped renderer: the Visualforce PDF rendering service, called from plain Apex
 * (ADR-0016).
 *
 * `Blob.toPdf()` renders HTML through the same service, with the same fonts and the same multi
 * byte support, as a Visualforce page rendered as PDF, without the callout semantics that cap a
 * batch `execute` at ten documents. That is the whole reason this feature can generate a year end
 * run at all.
 *
 * **Unverified in an org.** No Apex in this repository has been executed and no scratch org was
 * available, so ADR-0016's first spike, confirming that this call is not metered as a callout
 * inside `Database.Batchable` at the intended scope, is still open. If it turns out to be metered,
 * the fallback is a Visualforce `renderAs="pdf"` implementation of `ReceiptRenderer` and a change
 * to one setting: nothing else in the feature knows which implementation is in use.
 */
public with sharing class BlobToPdfReceiptRenderer implements ReceiptRenderer {
	public Blob render(String html) {
		if (String.isBlank(html)) {
			throw new ReceiptRendererException(Label.Giving_Receipt_NothingToRender);
		}
		return Blob.toPdf(html);
	}

	public String describe() {
		return 'Visualforce PDF rendering service (Blob.toPdf)';
	}

	public class ReceiptRendererException extends Exception {
	}
}
