/**
 * Multi-brand management (C-47, canonical model 29BR1 to 29BR3, ADR-0202 brand management and
 * visibility): the seam modules call, defaulting, and the rules the Brand triggers run.
 *
 * Off (`Brand_Management__c`, shipped false) every module-facing method returns without reading a
 * brand, so nothing anyone sees changes (R-BR2). Brands and legal entities are org configuration
 * every role may read, so they are read in system mode: a person issuing a receipt prints the
 * gift's brand whether or not they were granted the Brand object.
 */
@NamespaceAccessible
public with sharing class BrandService {
	@NamespaceAccessible
	public static final String BRAND_FIELD = 'Brand__c';

	/** A brand's printed identity (R-BR3). Blank values are left blank for the module to fill. */
	@NamespaceAccessible
	public class Profile {
		@NamespaceAccessible
		public Id brandId;
		@NamespaceAccessible
		public String brandName;
		@NamespaceAccessible
		public Id legalEntityId;
		@NamespaceAccessible
		public String legalName;
		@NamespaceAccessible
		public String taxId;
		@NamespaceAccessible
		public List<String> addressLines = new List<String>();
		@NamespaceAccessible
		public String phone;
		@NamespaceAccessible
		public String website;
		@NamespaceAccessible
		public String primaryColor;
		@NamespaceAccessible
		public String secondaryColor;
		@NamespaceAccessible
		public String senderEmail;
		@NamespaceAccessible
		public String signature;
		@NamespaceAccessible
		public String logoDocumentId;
		@NamespaceAccessible
		public String brandReceiptPrefix;
		@NamespaceAccessible
		public String entityReceiptPrefix;
	}

	@NamespaceAccessible
	public static Boolean isEnabled() {
		return SettingsService.getSettings().Brand_Management__c == true;
	}

	/** R-BR7: shares are kept only while both switches are on. */
	@NamespaceAccessible
	public static Boolean visibilityOn() {
		BarnCRM_Settings__c settings = SettingsService.getSettings();
		return settings.Brand_Management__c == true && settings.Brand_Visibility__c == true;
	}

	/** The brand's profile, the default brand's when `brandId` is blank, or null (R-BR3). */
	@NamespaceAccessible
	public static Profile profileFor(Id brandId) {
		if (!isEnabled()) {
			return null;
		}
		Id key = brandId != null ? brandId : defaultBrandId();
		return key == null ? null : profilesFor(new Set<Id>{ key }).get(key);
	}

	/** Profiles by brand ID, for a run that prints many records; empty while brands are off. */
	@NamespaceAccessible
	public static Map<Id, Profile> profilesFor(Set<Id> brandIds) {
		Map<Id, Profile> profiles = new Map<Id, Profile>();
		if (!isEnabled() || brandIds == null || brandIds.isEmpty()) {
			return profiles;
		}
		Id defaultEntity = defaultEntityId();
		Map<Id, Brand__c> brands = new Map<Id, Brand__c>(
			[
				SELECT
					Id,
					Name,
					Legal_Entity__c,
					Logo_Document_Id__c,
					Street__c,
					City__c,
					State__c,
					Postal_Code__c,
					Country__c,
					Phone__c,
					Website__c,
					Primary_Color__c,
					Secondary_Color__c,
					Sender_Email__c,
					Letter_Signature__c,
					Receipt_Number_Prefix__c
				FROM Brand__c
				WHERE Id IN :brandIds
				WITH SYSTEM_MODE
			]
		);
		Set<Id> entityIds = new Set<Id>{ defaultEntity };
		for (Brand__c brand : brands.values()) {
			entityIds.add(brand.Legal_Entity__c);
		}
		Map<Id, Legal_Entity__c> entities = new Map<Id, Legal_Entity__c>(
			[
				SELECT
					Id,
					Name,
					Tax_Id__c,
					Street__c,
					City__c,
					State__c,
					Postal_Code__c,
					Country__c,
					Receipt_Number_Prefix__c
				FROM Legal_Entity__c
				WHERE Id IN :entityIds
				WITH SYSTEM_MODE
			]
		);
		for (Brand__c brand : brands.values()) {
			Legal_Entity__c entity = entities.get(
				brand.Legal_Entity__c != null ? brand.Legal_Entity__c : defaultEntity
			);
			Profile profile = new Profile();
			profile.brandId = brand.Id;
			profile.brandName = brand.Name;
			profile.logoDocumentId = brand.Logo_Document_Id__c;
			profile.phone = brand.Phone__c;
			profile.website = brand.Website__c;
			profile.primaryColor = brand.Primary_Color__c;
			profile.secondaryColor = brand.Secondary_Color__c;
			profile.senderEmail = brand.Sender_Email__c;
			profile.signature = brand.Letter_Signature__c;
			profile.brandReceiptPrefix = brand.Receipt_Number_Prefix__c;
			profile.addressLines = addressLines(brand);
			if (entity != null) {
				profile.legalEntityId = entity.Id;
				profile.legalName = entity.Name;
				profile.taxId = entity.Tax_Id__c;
				profile.entityReceiptPrefix = entity.Receipt_Number_Prefix__c;
				if (profile.addressLines.isEmpty()) {
					profile.addressLines = addressLines(entity);
				}
			}
			profiles.put(brand.Id, profile);
		}
		return profiles;
	}

	/**
	 * R-BR5: the Organization-Wide Email Address each brand sends from, by brand ID. A brand whose
	 * Sender Email is blank or not set up as an organization-wide address is left out, so the
	 * caller keeps its own sender. Empty while brands are off.
	 */
	@NamespaceAccessible
	public static Map<Id, Id> senderIdsFor(Set<Id> brandIds) {
		Map<String, Set<Id>> brandsByAddress = new Map<String, Set<Id>>();
		for (Profile profile : profilesFor(brandIds).values()) {
			if (String.isNotBlank(profile.senderEmail)) {
				String key = profile.senderEmail.trim().toLowerCase();
				if (!brandsByAddress.containsKey(key)) {
					brandsByAddress.put(key, new Set<Id>());
				}
				brandsByAddress.get(key).add(profile.brandId);
			}
		}
		Map<Id, Id> senders = new Map<Id, Id>();
		if (brandsByAddress.isEmpty()) {
			return senders;
		}
		for (OrgWideEmailAddress address : [
			SELECT Id, Address
			FROM OrgWideEmailAddress
			WHERE Address IN :brandsByAddress.keySet()
			WITH SYSTEM_MODE
		]) {
			for (Id brandId : brandsByAddress.get(address.Address.toLowerCase())) {
				senders.put(brandId, address.Id);
			}
		}
		return senders;
	}

	/**
	 * R-BR5: the download path of the latest version of a brand's logo file, for an `img` in a
	 * document the PDF service renders (the receipt logo's shipped route, Giving R-RC13). Read in
	 * user mode: a file the user cannot see prints no logo. Null when there is none.
	 */
	@NamespaceAccessible
	public static String logoPath(String documentId) {
		Id fileId;
		try {
			fileId = Id.valueOf(documentId.trim());
		} catch (Exception notAnId) {
			return null;
		}
		List<ContentVersion> versions = [
			SELECT Id
			FROM ContentVersion
			WHERE ContentDocumentId = :fileId AND IsLatest = TRUE
			WITH USER_MODE
			LIMIT 1
		];
		return versions.isEmpty()
			? null
			: '/sfc/servlet.shepherd/version/download/' + versions[0].Id;
	}

	/**
	 * R-BR4: fills a blank `Brand__c` on new records from the parent's brand, then the creating
	 * user's primary or only brand. Call from a module's before insert. Does nothing while brands
	 * are off, or for a type without the field.
	 */
	@NamespaceAccessible
	public static void applyDefaults(List<SObject> records, String parentField) {
		if (records == null || records.isEmpty() || !isEnabled()) {
			return;
		}
		Map<String, Schema.SObjectField> fields = records[0]
			.getSObjectType()
			.getDescribe()
			.fields.getMap();
		if (!fields.containsKey(BRAND_FIELD.toLowerCase())) {
			return;
		}
		Map<Id, Id> parentBrands = parentBrands(records, fields, parentField);
		Id userBrand;
		Boolean userBrandRead = false;
		for (SObject record : records) {
			if (record.get(BRAND_FIELD) != null) {
				continue;
			}
			Id parentId = parentField == null ? null : (Id) record.get(parentField);
			Id brand = parentBrands.get(parentId);
			if (brand == null) {
				if (!userBrandRead) {
					userBrand = userBrandId(UserInfo.getUserId());
					userBrandRead = true;
				}
				brand = userBrand;
			}
			if (brand != null) {
				record.put(BRAND_FIELD, brand);
			}
		}
	}

	/** The user's primary brand, else their only active brand, else null. */
	@NamespaceAccessible
	public static Id userBrandId(Id userId) {
		Id only;
		Integer count = 0;
		for (Brand_Assignment__c assignment : [
			SELECT Brand__c, Is_Primary__c
			FROM Brand_Assignment__c
			WHERE User__c = :userId AND Brand__r.Active__c = TRUE
			WITH SYSTEM_MODE
			ORDER BY Is_Primary__c DESC
			LIMIT 2
		]) {
			if (assignment.Is_Primary__c) {
				return assignment.Brand__c;
			}
			only = assignment.Brand__c;
			count++;
		}
		return count == 1 ? only : null;
	}

	@NamespaceAccessible
	public static Id defaultBrandId() {
		List<Brand__c> rows = [
			SELECT Id
			FROM Brand__c
			WHERE Is_Default__c = TRUE AND Active__c = TRUE
			WITH SYSTEM_MODE
			ORDER BY CreatedDate
			LIMIT 1
		];
		return rows.isEmpty() ? null : rows[0].Id;
	}

	private static Id defaultEntityId() {
		List<Legal_Entity__c> rows = [
			SELECT Id
			FROM Legal_Entity__c
			WHERE Is_Default__c = TRUE
			WITH SYSTEM_MODE
			ORDER BY CreatedDate
			LIMIT 1
		];
		return rows.isEmpty() ? null : rows[0].Id;
	}

	private static Map<Id, Id> parentBrands(
		List<SObject> records,
		Map<String, Schema.SObjectField> fields,
		String parentField
	) {
		Map<Id, Id> brands = new Map<Id, Id>();
		if (String.isBlank(parentField) || !fields.containsKey(parentField.toLowerCase())) {
			return brands;
		}
		Set<Id> parentIds = new Set<Id>();
		for (SObject record : records) {
			if (record.get(BRAND_FIELD) == null && record.get(parentField) != null) {
				parentIds.add((Id) record.get(parentField));
			}
		}
		if (parentIds.isEmpty()) {
			return brands;
		}
		Schema.SObjectType parentType = new List<Id>(parentIds)[0].getSObjectType();
		if (!parentType.getDescribe().fields.getMap().containsKey(BRAND_FIELD.toLowerCase())) {
			return brands;
		}
		// Names come from describe, never input.
		String query = 'SELECT Id, Brand__c FROM ' + parentType + ' WHERE Id IN :parentIds';
		for (SObject parent : Database.query(query, AccessLevel.SYSTEM_MODE)) {
			brands.put(parent.Id, (Id) parent.get(BRAND_FIELD));
		}
		return brands;
	}

	/** Street; city, state and postal code on one line; country. Blank parts left out. */
	private static List<String> addressLines(SObject source) {
		List<String> lines = new List<String>();
		String locality = '';
		for (String part : new List<String>{ 'City__c', 'State__c', 'Postal_Code__c' }) {
			locality += String.isBlank((String) source.get(part)) ? '' : ' ' + source.get(part);
		}
		for (
			Object line : new List<Object>{
				source.get('Street__c'),
				locality,
				source.get('Country__c')
			}
		) {
			if (String.isNotBlank((String) line)) {
				lines.add(((String) line).trim());
			}
		}
		return lines;
	}

	// ---------------------------------------------------------------- trigger rules

	/** R-BR1: saving a brand or entity as Default clears it on every other one. */
	public static void keepOneDefault(List<SObject> records) {
		Set<Id> newDefaults = new Set<Id>();
		for (SObject record : records) {
			if (record.get('Is_Default__c') == true) {
				newDefaults.add(record.Id);
			}
		}
		if (newDefaults.isEmpty()) {
			return;
		}
		Schema.SObjectType type = records[0].getSObjectType();
		List<SObject> others = new List<SObject>();
		// The type is the trigger's own object.
		String query =
			'SELECT Id FROM ' +
			type +
			' WHERE Is_Default__c = TRUE AND Id NOT IN :newDefaults';
		for (SObject other : Database.query(query, AccessLevel.SYSTEM_MODE)) {
			other.put('Is_Default__c', false);
			others.add(other);
		}
		BrandShareWriter.updateRecords(others);
	}

	/** R-BR9: sets the key, and keeps one primary per assigned record. */
	public static void prepareAssignments(List<Brand_Assignment__c> assignments) {
		for (Brand_Assignment__c assignment : assignments) {
			Id target = targetOf(assignment);
			assignment.Assignment_Key__c = target == null
				? null
				: String.valueOf(assignment.Brand__c) + String.valueOf(target);
		}
	}

	public static void keepOnePrimary(List<Brand_Assignment__c> assignments) {
		Set<Id> targets = new Set<Id>();
		Set<Id> primaries = new Set<Id>();
		for (Brand_Assignment__c assignment : assignments) {
			if (assignment.Is_Primary__c && targetOf(assignment) != null) {
				targets.add(targetOf(assignment));
				primaries.add(assignment.Id);
			}
		}
		if (targets.isEmpty()) {
			return;
		}
		List<Brand_Assignment__c> others = [
			SELECT Id
			FROM Brand_Assignment__c
			WHERE
				Is_Primary__c = TRUE
				AND Id NOT IN :primaries
				AND (Contact__c IN :targets
				OR Account__c IN :targets
				OR User__c IN :targets)
			WITH SYSTEM_MODE
		];
		for (Brand_Assignment__c other : others) {
			other.Is_Primary__c = false;
		}
		BrandShareWriter.updateRecords(others);
	}

	public static Id targetOf(Brand_Assignment__c assignment) {
		return assignment.Contact__c != null
			? assignment.Contact__c
			: assignment.Account__c != null ? assignment.Account__c : assignment.User__c;
	}
}
