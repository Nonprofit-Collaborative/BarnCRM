/**
 * Radius Find (C-69, canonical model R-SQ13): a condition that keeps the records whose address
 * is within a number of miles of a point, using the geocodes Salesforce already stores on
 * addresses and SOQL `DISTANCE`, with no outside geocoding.
 *
 * The point is a US postal code, read from the shipped `BarnZipCentroids` static resource (one
 * internal point per ZCTA from the US Census Bureau 2023 Gazetteer, ADR-0179), or the
 * address of a record the person names, read from that record's own geocode. It reaches the
 * query as two numbers, so the query document holds `{ field, miles, latitude, longitude }` and
 * nothing a person typed ever becomes query text.
 *
 * Every name comes from the running user's describe: the field must be a compound address or a
 * location field of the query's object that the user can read. Latitude, longitude and miles
 * are bind variables. A record whose address has no geocode is never within a distance; the
 * count of those with a postal code is reported so the person is told why they are missing.
 */
public with sharing class FindRadius {
	public static final Integer MIN_MILES = 1;
	public static final Integer MAX_MILES = 500;
	private static final String RESOURCE = 'BarnZipCentroids';
	private static final Pattern POSTAL = Pattern.compile('^(\\d{5})(-\\d{4})?$');
	private static final Pattern RECORD_ID = Pattern.compile('^([a-zA-Z0-9]{15}|[a-zA-Z0-9]{18})$');
	private static final Pattern NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');

	/** Raised when the radius cannot be used; the message is for the person. */
	public class FindRadiusException extends Exception {
	}

	/** A point on the map and where it came from. */
	public class Center {
		@AuraEnabled
		public Decimal latitude;
		@AuraEnabled
		public Decimal longitude;
		/** What the point is, for the screen (`Postal code 02134` or the record's address). */
		@AuraEnabled
		public String label;
		/** Set when the point is a stand in, for example a postal code used for want of a geocode. */
		@AuraEnabled
		public String note;
	}

	/** One address or location field of an object the user can read. */
	public class FieldOption {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;
	}

	/** The shipped table, read once per transaction; a test replaces it. */
	@TestVisible
	private static String tableForTest;
	private static String table;

	/** Compound address and location fields of the object the person can read, by label. */
	public static List<FieldOption> fieldOptions(String objectName) {
		Schema.DescribeSObjectResult described = QueryFieldCatalog.describeObject(objectName);
		Map<String, FieldOption> byLabel = new Map<String, FieldOption>();
		for (Schema.SObjectField field : described.fields.getMap().values()) {
			Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
			if (!isGeocodable(fieldDescribe)) {
				continue;
			}
			FieldOption option = new FieldOption();
			option.label = fieldDescribe.getLabel();
			option.value = fieldDescribe.getName();
			byLabel.put(option.label.toLowerCase() + '\u0000' + option.value, option);
		}
		List<String> keys = new List<String>(byLabel.keySet());
		keys.sort();
		List<FieldOption> options = new List<FieldOption>();
		for (String key : keys) {
			options.add(byLabel.get(key));
		}
		return options;
	}

	/** The centroid of a US postal code (`02134` or `02134-1234`), or null when it is not shipped. */
	public static Center centroid(String postalCode) {
		Matcher matcher = POSTAL.matcher(String.isBlank(postalCode) ? '' : postalCode.trim());
		if (!matcher.matches()) {
			return null;
		}
		String zip = matcher.group(1);
		String data = table();
		Integer start = data.indexOf(';' + zip + ',');
		if (start < 0) {
			return null;
		}
		List<String> parts = data.substring(start + 1, data.indexOf(';', start + 1)).split(',');
		Center center = new Center();
		center.latitude = Decimal.valueOf(parts[1]);
		center.longitude = Decimal.valueOf(parts[2]);
		center.label = String.format(
			BarnHelp.text('Core', 'Core_Find_RadiusPostalLabel'),
			new List<Object>{ zip }
		);
		return center;
	}

	/**
	 * The point a person typed: a US postal code, or the Id of a record whose address is used.
	 * The record's own geocode wins; with none, its postal code stands in and says so.
	 */
	public static Center resolveCenter(String text) {
		String given = String.isBlank(text) ? '' : text.trim();
		if (given == '') {
			throw new FindRadiusException(BarnHelp.text('Core', 'Core_Find_RadiusNoCenter'));
		}
		if (POSTAL.matcher(given).matches()) {
			Center found = centroid(given);
			if (found == null) {
				throw new FindRadiusException(
					String.format(
						BarnHelp.text('Core', 'Core_Find_RadiusUnknownPostal'),
						new List<Object>{ given }
					)
				);
			}
			return found;
		}
		if (RECORD_ID.matcher(given).matches()) {
			return recordCenter(given);
		}
		throw new FindRadiusException(
			String.format(
				BarnHelp.text('Core', 'Core_Find_RadiusNotAPlace'),
				new List<Object>{ given.abbreviate(40) }
			)
		);
	}

	/** The condition for a document's `radius`: a clause with bind names, its binds and display. */
	public static FindRelatedRecords.Rendered condition(String objectName, Object rawRadius) {
		if (!(rawRadius instanceof Map<String, Object>)) {
			throw new FindRadiusException(BarnHelp.text('Core', 'Core_Find_ErrorInvalidQuery'));
		}
		Map<String, Object> radius = (Map<String, Object>) rawRadius;
		String fieldName = String.valueOf(radius.get('field'));
		checkField(objectName, fieldName);
		Decimal miles = number(radius.get('miles'));
		Decimal latitude = number(radius.get('latitude'));
		Decimal longitude = number(radius.get('longitude'));
		if (
			miles == null ||
			miles < MIN_MILES ||
			miles > MAX_MILES ||
			miles.stripTrailingZeros().scale() > 0
		) {
			throw new FindRadiusException(
				String.format(
					BarnHelp.text('Core', 'Core_Find_RadiusMiles'),
					new List<Object>{ MIN_MILES, MAX_MILES }
				)
			);
		}
		if (
			latitude == null ||
			longitude == null ||
			latitude < -90 ||
			latitude > 90 ||
			longitude < -180 ||
			longitude > 180
		) {
			throw new FindRadiusException(BarnHelp.text('Core', 'Core_Find_RadiusNoCenter'));
		}
		FindRelatedRecords.Rendered rendered = new FindRelatedRecords.Rendered();
		rendered.clause =
			boundingBox(fieldName, rendered.binds, latitude, longitude, miles) +
			'DISTANCE(' +
			fieldName +
			', GEOLOCATION(:radiusLatitude, :radiusLongitude), \'mi\') < :radiusMiles';
		rendered.binds.put('radiusLatitude', latitude);
		rendered.binds.put('radiusLongitude', longitude);
		rendered.binds.put('radiusMiles', miles);
		rendered.display =
			'DISTANCE(' +
			fieldName +
			', GEOLOCATION(' +
			latitude.toPlainString() +
			', ' +
			longitude.toPlainString() +
			'), \'mi\') < ' +
			miles.toPlainString();
		return rendered;
	}

	/**
	 * SOQL that keeps records with a postal code but no geocode on a standard compound address
	 * (`MailingAddress` reads `MailingLatitude` and `MailingPostalCode`), or null when the field
	 * has no such pair, as a location field has none.
	 */
	public static String missingGeocodeClause(String objectName, String fieldName) {
		checkField(objectName, fieldName);
		if (!fieldName.endsWith('Address')) {
			return null;
		}
		String prefix = fieldName.removeEnd('Address');
		Map<String, Schema.SObjectField> fields = QueryFieldCatalog.describeObject(objectName)
			.fields.getMap();
		for (String part : new List<String>{ 'Latitude', 'PostalCode' }) {
			Schema.SObjectField found = fields.get(prefix + part);
			if (found == null || !found.getDescribe().isAccessible()) {
				return null;
			}
		}
		return '(' + prefix + 'Latitude = NULL AND ' + prefix + 'PostalCode != NULL)';
	}

	// ------------------------------------------------------------------------------ helpers

	/**
	 * Latitude and longitude ranges that hold the whole circle, ANDed ahead of DISTANCE so
	 * the query narrows on plain number comparisons before measuring each row (D-200 P13).
	 * One degree of latitude is about 69 miles; a degree of longitude shrinks by the cosine
	 * of the latitude. Near a pole or across the date line the longitude range is left off,
	 * and DISTANCE alone decides, as before.
	 */
	private static String boundingBox(
		String fieldName,
		Map<String, Object> binds,
		Decimal latitude,
		Decimal longitude,
		Decimal miles
	) {
		String stem = fieldName.endsWith('__c')
			? fieldName.removeEnd('__c') + '__'
			: fieldName.removeEnd('Address');
		String suffix = fieldName.endsWith('__c') ? '__s' : '';
		String latitudeName = stem + 'Latitude' + suffix;
		String longitudeName = stem + 'Longitude' + suffix;
		Double centerLatitude = latitude.doubleValue();
		Double centerLongitude = longitude.doubleValue();
		// 68.5 miles per degree, a touch under the true 69, so the box is never too small.
		Double latitudeSpan = miles.doubleValue() * 2 / 137;
		binds.put('boxSouth', centerLatitude - latitudeSpan);
		binds.put('boxNorth', centerLatitude + latitudeSpan);
		String clause = latitudeName + ' >= :boxSouth AND ' + latitudeName + ' <= :boxNorth AND ';
		Double cosine = Math.cos(Math.abs(centerLatitude) * Math.PI / 180);
		Double longitudeSpan = 360;
		if (cosine > 0) {
			longitudeSpan = latitudeSpan / cosine;
		}
		if (
			Math.abs(centerLatitude) + latitudeSpan >= 89 ||
			Math.abs(centerLongitude) + longitudeSpan >= 180
		) {
			return clause;
		}
		binds.put('boxWest', centerLongitude - longitudeSpan);
		binds.put('boxEast', centerLongitude + longitudeSpan);
		return clause + longitudeName + ' >= :boxWest AND ' + longitudeName + ' <= :boxEast AND ';
	}

	private static Boolean isGeocodable(Schema.DescribeFieldResult field) {
		Schema.DisplayType type = field.getType();
		return (type == Schema.DisplayType.ADDRESS || type == Schema.DisplayType.LOCATION) &&
			field.isAccessible();
	}

	private static void checkField(String objectName, String fieldName) {
		Schema.DescribeSObjectResult described = QueryFieldCatalog.describeObject(objectName);
		Schema.SObjectField field = fieldName == null || !NAME.matcher(fieldName).matches()
			? null
			: described.fields.getMap().get(fieldName);
		if (field == null || !isGeocodable(field.getDescribe())) {
			throw new FindRadiusException(
				String.format(
					BarnHelp.text('Core', 'Core_Find_RadiusField'),
					new List<Object>{ String.valueOf(fieldName).abbreviate(80) }
				)
			);
		}
	}

	private static Decimal number(Object raw) {
		if (raw == null) {
			return null;
		}
		try {
			return Decimal.valueOf(String.valueOf(raw).trim());
		} catch (Exception notANumber) {
			return null;
		}
	}

	private static String table() {
		if (tableForTest != null) {
			return tableForTest;
		}
		if (table == null) {
			String body = SetupObjectSelector.staticResourceBody(RESOURCE);
			table = body == null ? ';' : ';' + body.trim() + ';';
		}
		return table;
	}

	/** A record's own geocode, read as the person; its postal code stands in when it has none. */
	private static Center recordCenter(String recordId) {
		Id wanted;
		try {
			wanted = Id.valueOf(recordId);
		} catch (Exception notAnId) {
			throw new FindRadiusException(
				String.format(
					BarnHelp.text('Core', 'Core_Find_RadiusNotAPlace'),
					new List<Object>{ recordId.abbreviate(40) }
				)
			);
		}
		Schema.DescribeSObjectResult described = QueryFieldCatalog.describeObject(
			wanted.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).getName()
		);
		Map<String, Schema.SObjectField> fields = described.fields.getMap();
		List<String> selected = new List<String>();
		for (Schema.SObjectField field : fields.values()) {
			Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
			if (!isGeocodable(fieldDescribe)) {
				continue;
			}
			String name = fieldDescribe.getName();
			if (fieldDescribe.getType() == Schema.DisplayType.LOCATION) {
				String stem = name.removeEnd('__c');
				selected.add(stem + '__Latitude__s');
				selected.add(stem + '__Longitude__s');
			} else {
				String prefix = name.removeEnd('Address');
				for (String part : new List<String>{ 'Latitude', 'Longitude', 'PostalCode' }) {
					if (fields.containsKey(prefix + part)) {
						selected.add(prefix + part);
					}
				}
			}
		}
		if (selected.isEmpty()) {
			throw new FindRadiusException(
				String.format(
					BarnHelp.text('Core', 'Core_Find_RadiusNoAddress'),
					new List<Object>{ described.getLabel() }
				)
			);
		}
		List<SObject> found = Database.queryWithBinds(
			'SELECT ' +
				String.join(selected, ', ') +
				' FROM ' +
				described.getName() +
				' WHERE Id = :recordId LIMIT 1',
			new Map<String, Object>{ 'recordId' => wanted },
			AccessLevel.USER_MODE
		);
		if (found.isEmpty()) {
			throw new FindRadiusException(BarnHelp.text('Core', 'Core_Find_RadiusNoRecord'));
		}
		return centerOf(found[0], selected, described.getLabel());
	}

	private static Center centerOf(SObject record, List<String> selected, String objectLabel) {
		String postal;
		for (String name : selected) {
			if (name.endsWith('PostalCode') && postal == null) {
				postal = (String) record.get(name);
			}
		}
		for (String name : selected) {
			String latitudeName = name.endsWith('Latitude') || name.endsWith('__Latitude__s')
				? name
				: null;
			if (latitudeName == null) {
				continue;
			}
			String longitudeName = latitudeName.endsWith('__Latitude__s')
				? latitudeName.removeEnd('__Latitude__s') + '__Longitude__s'
				: latitudeName.removeEnd('Latitude') + 'Longitude';
			Decimal latitude = (Decimal) record.get(latitudeName);
			Decimal longitude = (Decimal) record.get(longitudeName);
			if (latitude != null && longitude != null) {
				Center center = new Center();
				center.latitude = latitude;
				center.longitude = longitude;
				center.label = String.format(
					BarnHelp.text('Core', 'Core_Find_RadiusRecordLabel'),
					new List<Object>{ objectLabel }
				);
				return center;
			}
		}
		Center stand = postal == null ? null : centroid(postal);
		if (stand == null) {
			throw new FindRadiusException(BarnHelp.text('Core', 'Core_Find_RadiusNoGeocode'));
		}
		stand.note = BarnHelp.text('Core', 'Core_Find_RadiusStandIn');
		return stand;
	}
}
