/**
 * Print on an invoice (PM-10; ADR-NEXT `NEXT-projects-psa.md` decision 6): a PDF of the invoice
 * made from HTML with `Blob.toPdf`, as Giving's receipts are, saved to the invoice's Files. No
 * Visualforce page. User mode; needs Manage Projects and Create invoices on.
 */
public with sharing class ProjectInvoiceDocument {
	/** Saves the PDF to the invoice's Files and returns its ContentDocumentId. */
	public static Id print(Id invoiceId) {
		ProjectBilling.requireBilling();
		Project_Invoice__c invoice = [
			SELECT
				Name,
				Status__c,
				Invoice_Date__c,
				Due_Date__c,
				Period_Start__c,
				Period_End__c,
				Total__c,
				Amount_Paid__c,
				Notes__c,
				Account__r.Name,
				Contact__r.Name,
				Project__r.Name,
				(
					SELECT Description__c, Service_Date__c, Quantity__c, Unit_Price__c, Amount__c
					FROM Lines__r
					ORDER BY Service_Date__c, Name
					LIMIT 2000
				)
			FROM Project_Invoice__c
			WHERE Id = :invoiceId
			WITH USER_MODE
		];
		ContentVersion file = new ContentVersion(
			Title = invoice.Name,
			PathOnClient = invoice.Name + '.pdf',
			VersionData = Blob.toPdf(html(invoice)),
			FirstPublishLocationId = invoiceId
		);
		insert as user file;
		return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :file.Id WITH USER_MODE]
		.ContentDocumentId;
	}

	/** The invoice as HTML; every value is escaped. Labels come from the help catalog. */
	@TestVisible
	private static String html(Project_Invoice__c invoice) {
		// Invoice, Bill To, Invoice Date, Due Date, Period, Total, Amount Paid, Balance Due, Notes.
		List<String> label = BarnHelp.text('Projects', 'Projects_Invoice_PdfLabels').split('\\|');
		List<String> head = BarnHelp.text('Projects', 'Projects_Invoice_PdfColumns').split('\\|');
		String out =
			'<html><body style="font-family: sans-serif; font-size: 11pt;">' +
			'<h1>' +
			esc(UserInfo.getOrganizationName()) +
			'</h1><h2>' +
			esc(label[0]) +
			' ' +
			esc(invoice.Name) +
			'</h2><p>' +
			esc(invoice.Project__r.Name) +
			'</p><table cellpadding="4">' +
			row(label[1], billTo(invoice)) +
			row(label[2], day(invoice.Invoice_Date__c)) +
			row(label[3], day(invoice.Due_Date__c)) +
			row(label[4], day(invoice.Period_Start__c) + ' - ' + day(invoice.Period_End__c)) +
			'</table><table width="100%" cellpadding="4" style="border-collapse: collapse;"><tr>';
		for (String heading : head) {
			out +=
				'<th align="left" style="border-bottom: 1px solid #000;">' +
				esc(heading) +
				'</th>';
		}
		out += '</tr>';
		for (Project_Invoice_Line__c line : invoice.Lines__r) {
			out +=
				'<tr><td>' +
				esc(line.Description__c) +
				'</td><td>' +
				esc(day(line.Service_Date__c)) +
				'</td><td>' +
				esc(String.valueOf(line.Quantity__c)) +
				'</td><td>' +
				esc(money(line.Unit_Price__c)) +
				'</td><td>' +
				esc(money(line.Amount__c)) +
				'</td></tr>';
		}
		Decimal total = invoice.Total__c == null ? 0 : invoice.Total__c;
		Decimal paid = invoice.Amount_Paid__c == null ? 0 : invoice.Amount_Paid__c;
		out +=
			'</table><table cellpadding="4" align="right">' +
			row(label[5], money(total)) +
			row(label[6], money(paid)) +
			row(label[7], money(total - paid)) +
			'</table>';
		if (String.isNotBlank(invoice.Notes__c)) {
			out +=
				'<p style="clear: both;"><b>' +
				esc(label[8]) +
				'</b><br/>' +
				esc(invoice.Notes__c).replace('\n', '<br/>') +
				'</p>';
		}
		return out + '</body></html>';
	}

	private static String row(String name, String value) {
		return '<tr><td><b>' + esc(name) + '</b></td><td>' + esc(value) + '</td></tr>';
	}

	private static String billTo(Project_Invoice__c invoice) {
		List<String> names = new List<String>();
		for (String name : new List<String>{ invoice.Account__r?.Name, invoice.Contact__r?.Name }) {
			if (name != null) {
				names.add(name);
			}
		}
		return String.join(names, ', ');
	}

	private static String day(Date value) {
		return value == null ? '' : value.format();
	}

	private static String money(Decimal value) {
		return value == null ? '' : String.valueOf(value.setScale(2));
	}

	private static String esc(String value) {
		return value == null ? '' : value.escapeHtml4();
	}
}
