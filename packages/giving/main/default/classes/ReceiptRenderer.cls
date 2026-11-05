/**
 * The one seam between composing a receipt and rendering it (ADR-0016).
 *
 * Everything above this line composes HTML and knows nothing about PDFs; everything below it
 * turns HTML into bytes and knows nothing about receipts. The package ships one implementation,
 * `BlobToPdfReceiptRenderer`, which calls the Visualforce PDF rendering service from plain Apex.
 * ADR-0016 names a Visualforce `renderAs="pdf"` implementation as the fallback if the spike that
 * confirms `Blob.toPdf()` is not metered as a callout inside a batch fails. That spike needs a
 * real org and has not been run, which is precisely why this interface exists: swapping the
 * implementation is one class and one setting, not a rewrite.
 *
 * `@NamespaceAccessible public` rather than `global`, per ADR-0017: this is a seam other packages
 * in the namespace may implement, not a permanent subscriber-facing API.
 */
@NamespaceAccessible
public interface ReceiptRenderer {
	/**
	 * The PDF bytes for one composed document.
	 *
	 * @param html a complete HTML document, already merged and already carrying the tax
	 *        sentences `ReceiptContentBuilder` is responsible for.
	 * @return the rendered PDF.
	 */
	Blob render(String html);

	/**
	 * What this renderer is, in a few words, for the Error Log and the run record. A failed
	 * year end run should say which renderer produced the failure without anyone reading code.
	 */
	String describe();
}
