/**
 * The system mode writes of multi-brand management (C-47, ADR-0202 brand management and
 * visibility): one-default and one-primary upkeep on Brand, Legal Entity and Brand Assignment,
 * and the brand groups, their members and the Account shares granted to them (R-BR7).
 *
 * `without sharing` under ADR-0021 (Platform and Upkeep): a staff member who assigns a brand
 * cannot create a public group, add members to it, or share an Account they do not own, and the
 * one-primary rule must clear a flag on an assignment the saver may not edit. Every caller
 * builds the rows itself from BarnCRM's own data; no user text reaches a write here, and only
 * groups named `BarnCRM_Brand_` and shares granted to them are ever touched.
 */
public without sharing class BrandShareWriter {
	public static void updateRecords(List<SObject> rows) {
		if (rows != null && !rows.isEmpty()) {
			Database.update(rows, true, AccessLevel.SYSTEM_MODE);
		}
	}

	public static void insertRows(List<SObject> rows) {
		if (rows != null && !rows.isEmpty()) {
			// Not all or none: one Account deleted mid run must not stop the rest.
			for (
				Database.SaveResult result : Database.insert(rows, false, AccessLevel.SYSTEM_MODE)
			) {
				if (!result.isSuccess()) {
					ErrorLogger.logMessage(
						String.valueOf(result.getErrors()[0].getMessage()),
						'BrandShareWriter.insertRows',
						ErrorLogger.SEVERITY_WARNING
					);
				}
			}
		}
	}

	public static void deleteRows(List<SObject> rows) {
		if (rows != null && !rows.isEmpty()) {
			Database.delete(rows, false, AccessLevel.SYSTEM_MODE);
		}
	}
}
