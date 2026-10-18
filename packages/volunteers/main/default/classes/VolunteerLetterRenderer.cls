/**
 * Turns a merged letter into a PDF through the Visualforce PDF rendering service, called from
 * plain Apex with `Blob.toPdf()` (ADR-0016, ADR-0129). The technique Giving's receipt renderer
 * uses, restated here so Volunteers does not need Giving.
 *
 * Virtual so a bulk test can stand in a renderer that skips the PDF service and measures only
 * the generator's own queries and saves. If `Blob.toPdf()` turns out to be metered inside a
 * batch, a Visualforce `renderAs="pdf"` page goes behind this class and nothing else changes.
 */
public with sharing virtual class VolunteerLetterRenderer {
    public virtual Blob render(String html) {
        return Blob.toPdf(html);
    }
}
