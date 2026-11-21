/**
 * Export Recipe, Import Recipe and template import on Super Connector (CN-08; canonical model
 * R-CR13 to R-CR15; design Sections 3.6 and 3.8; D-216; security review F1, F4, F7).
 *
 * Nothing here stores anything. Export returns a file's text; import reads a file's text, checks
 * it as Save and Publish would, matches the maps, import templates and connections it names to
 * this org's by name, and returns what the page offers: a New Connection form filled in and each
 * recipe as an unsaved draft. A file is refused when it holds `{!` anywhere (F1), a key named
 * like a secret, a Bearer or Basic sign-in value, a literal value in a sign-in-like header, an
 * auth header template or a formula option (R-CR15): no secret ever travels in a file.
 */
public with sharing class ConnectorRecipeFiles {
	public static final Integer MAX_FILE = 400000;
	public static final Integer MAX_TEMPLATE_RECIPES = 10;
	public static final String RECIPE = 'recipe';
	public static final String TEMPLATE = 'template';
	private static final Set<String> SECRET_KEYS = new Set<String>{
		'password',
		'secret',
		'clientsecret',
		'token',
		'accesstoken',
		'refreshtoken',
		'apikey',
		'apisecret',
		'authorization',
		'credential',
		'privatekey',
		'secreturl'
	};
	private static final Set<String> FORMULA_KEYS = new Set<String>{
		'header',
		'headervalue',
		'headertemplate',
		'formula',
		'allowmergefieldsinbody',
		'allowmergefieldsinheader'
	};
	/** A Bearer or Basic sign-in value: the word, then a run of 12 or more token characters with a digit. */
	private static final Pattern SIGN_IN_VALUE = Pattern.compile(
		'(?i)\\s*(bearer|basic)\\s+(?=[A-Za-z._~+/=-]*[0-9])[A-Za-z0-9._~+/=-]{12,}\\s*'
	);
	private static final Pattern PLACEHOLDER = Pattern.compile('\\{([A-Za-z0-9_]{1,40})\\}');
	private static final Pattern BASE_URL = Pattern.compile(
		'https://[A-Za-z0-9.{}_-]{1,253}(:[0-9]{1,5})?(/[A-Za-z0-9._~%!$&\'()*+,;=:/-]*)?'
	);
	private static final Set<String> ENVELOPE_KEYS = new Set<String>{
		'barnRecipe',
		'name',
		'description',
		'recipe',
		'names'
	};
	private static final Set<String> TEMPLATE_KEYS = new Set<String>{
		'key',
		'label',
		'version',
		'description',
		'auth',
		'baseUrl',
		'urlParams',
		'check',
		'actions',
		'pollers',
		'webhook',
		'requires',
		'recipes'
	};
	private static final Set<String> AUTH_KEYS = new Set<String>{ 'kind', 'headerName', 'params' };
	private static final Set<String> PARAM_KEYS = new Set<String>{
		'name',
		'label',
		'help',
		'pattern',
		'fromParam',
		'after'
	};
	private static final Set<String> ACTION_KEYS = new Set<String>{
		'key',
		'label',
		'method',
		'path',
		'query',
		'inputs',
		'body'
	};
	private static final Set<String> TEMPLATE_RECIPE_KEYS = new Set<String>{ 'name', 'description', 'draft' };

	/** What an import offers the page. */
	public class Imported {
		@AuraEnabled
		public String kind;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String description;
		@AuraEnabled
		public Prefill connection;
		@AuraEnabled
		public List<Draft> recipes = new List<Draft>();
	}

	/** A template's New Connection form: never a key (R-CR14). */
	public class Prefill {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String authKind;
		@AuraEnabled
		public String headerName;
		@AuraEnabled
		public String baseUrl;
		@AuraEnabled
		public List<UrlParam> urlParams = new List<UrlParam>();
		/** The template's check path, which Check Connection asks for (e1); blank is the base URL. */
		@AuraEnabled
		public String checkPath;
	}

	public class UrlParam {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String help;
		@AuraEnabled
		public String pattern;
		@AuraEnabled
		public String fromParam;
		@AuraEnabled
		public String after;
	}

	/** One recipe to open as an unsaved draft, with what Publish would still refuse. */
	public class Draft {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String description;
		@AuraEnabled
		public String draftJson;
		/** Step names with blanks to fill. */
		@AuraEnabled
		public List<String> blanks = new List<String>();
		/** What Publish would refuse once the blanks are filled. */
		@AuraEnabled
		public List<String> problems = new List<String>();
	}

	/** A refusal, written for a person. */
	public class FileException extends Exception {
	}

	// ---------------------------------------------------------------------------------------
	// Export Recipe
	// ---------------------------------------------------------------------------------------

	/**
	 * The recipe as a file (R-CR13): its published definition (the draft before the first
	 * Publish) without sample data or sign-in header values, and the names of the maps, import
	 * templates and connections it uses. No Run As, owner, run or key.
	 */
	public static String export(Id recipeId) {
		ConnectorConnections.requireManager();
		List<Connector_Recipe__c> rows = [
			SELECT Name, Description__c, Definition_JSON__c, Draft_JSON__c
			FROM Connector_Recipe__c
			WHERE Id = :recipeId
			WITH USER_MODE
			LIMIT 1
		];
		if (rows.isEmpty()) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Recipe_ErrorGone'));
		}
		Connector_Recipe__c row = rows[0];
		Map<String, Object> document = ConnectorRecipeDocument.parse(
			String.isBlank(row.Definition_JSON__c) ? row.Draft_JSON__c : row.Definition_JSON__c
		);
		ConnectorRecipeDocument.mapOf(document.get('trigger')).remove('sample');
		ConnectorRecipeDocument.mapOf(document.get('trigger')).remove('savedQuery');
		Set<String> recordIds = new Set<String>();
		Set<String> connections = new Set<String>();
		// An App Poll trigger asks an app as Call an App does (R-CR16): its connection travels by
		// label and a typed sign-in header value is left blank.
		Map<String, Object> starter = ConnectorRecipeDocument.mapOf(document.get('trigger'));
		if (String.isNotBlank(ConnectorRecipeDocument.textOf(starter.get('connection')))) {
			connections.add(ConnectorRecipeDocument.textOf(starter.get('connection')));
		}
		for (Object raw : ConnectorRecipeDocument.listOf(starter.get('headers'))) {
			if (signInHeader(ConnectorRecipeDocument.mapOf(raw))) {
				ConnectorRecipeDocument.mapOf(raw).put('value', '');
			}
		}
		for (Map<String, Object> step : ConnectorRecipeDocument.allSteps(document)) {
			step.remove('savedQuery');
			for (String key : new List<String>{ 'map', 'bodyMap', 'template' }) {
				if (ConnectorRecipeDocument.isId(ConnectorRecipeDocument.textOf(step.get(key)))) {
					recordIds.add(ConnectorRecipeDocument.textOf(step.get(key)));
				}
			}
			if (String.isNotBlank(ConnectorRecipeDocument.textOf(step.get('connection')))) {
				connections.add(ConnectorRecipeDocument.textOf(step.get('connection')));
			}
			blankSignInHeaders(step);
		}
		Map<String, Object> names = new Map<String, Object>();
		for (Saved_Transform__c saved : [
			SELECT Id, Name
			FROM Saved_Transform__c
			WHERE Id IN :recordIds
			WITH USER_MODE
		]) {
			names.put(saved.Id, saved.Name);
		}
		for (Import_Template__c template : [
			SELECT Id, Name
			FROM Import_Template__c
			WHERE Id IN :recordIds
			WITH USER_MODE
		]) {
			names.put(template.Id, template.Name);
		}
		if (!connections.isEmpty()) {
			for (ConnectorConnections.Connection connection : ConnectorConnections.page().connections) {
				if (connections.contains(connection.name)) {
					names.put(connection.name, connection.label);
				}
			}
		}
		return JSON.serializePretty(
			new Map<String, Object>{
				'barnRecipe' => 1,
				'name' => row.Name,
				'description' => row.Description__c,
				'recipe' => document,
				'names' => names
			}
		);
	}

	/** A header whose name says it signs in keeps its name, never a typed value (R-CR15). */
	private static void blankSignInHeaders(Map<String, Object> step) {
		Boolean blanked = false;
		for (Object raw : ConnectorRecipeDocument.listOf(step.get('headers'))) {
			Map<String, Object> header = ConnectorRecipeDocument.mapOf(raw);
			if (signInHeader(header)) {
				header.put('value', '');
				blanked = true;
			}
		}
		if (blanked) {
			addFill(step, 'headers');
		}
	}

	private static Boolean signInHeader(Map<String, Object> header) {
		return ConnectorRecipeDocument.literalSignIn(header);
	}

	// ---------------------------------------------------------------------------------------
	// Import: a recipe file or a template
	// ---------------------------------------------------------------------------------------

	/** Reads a recipe file or a template (R-CR13, R-CR14); stores nothing. */
	public static Imported read(String source) {
		ConnectorConnections.requireManager();
		if (String.isBlank(source) || source.length() > MAX_FILE) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorSize', detail(null)));
		}
		Object raw;
		try {
			raw = JSON.deserializeUntyped(source);
		} catch (Exception unreadable) {
			raw = null;
		}
		if (!(raw instanceof Map<String, Object>)) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorUnreadable', detail(null)));
		}
		// Serialized again, so a `{!` written with JSON escapes is caught as well (F1).
		if (JSON.serialize(raw).contains('{!')) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorMergeField', detail(null)));
		}
		scan(raw);
		Map<String, Object> file = (Map<String, Object>) raw;
		return file.containsKey('barnRecipe') ? recipeFile(file) : template(file);
	}

	/** Refuses a secret or a formula option anywhere (R-CR15, F1). */
	@TestVisible
	private static void scan(Object value) {
		if (value instanceof Map<String, Object>) {
			Map<String, Object> entries = (Map<String, Object>) value;
			for (String key : entries.keySet()) {
				String plain = key.toLowerCase().replace('-', '').replace('_', '');
				if (SECRET_KEYS.contains(plain)) {
					throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorSecret', detail(key)));
				}
				if (FORMULA_KEYS.contains(plain)) {
					throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorFormula', detail(key)));
				}
				scan(entries.get(key));
			}
			for (Object header : ConnectorRecipeDocument.listOf(entries.get('headers'))) {
				if (signInHeader(ConnectorRecipeDocument.mapOf(header))) {
					throw refusal(
						BarnHelp.text(
							'Connector',
							'Connector_Import_ErrorSecret',
							detail(ConnectorRecipeDocument.mapOf(header).get('name'))
						)
					);
				}
			}
		} else if (value instanceof List<Object>) {
			for (Object item : (List<Object>) value) {
				scan(item);
			}
		} else if (value instanceof String && SIGN_IN_VALUE.matcher((String) value).matches()) {
			throw refusal(
				BarnHelp.text(
					'Connector',
					'Connector_Import_ErrorSecret',
					detail(((String) value).trim().substringBefore(' '))
				)
			);
		}
	}

	private static Imported recipeFile(Map<String, Object> file) {
		refuseUnknown(file, ENVELOPE_KEYS);
		if (file.get('barnRecipe') != 1 || !(file.get('recipe') instanceof Map<String, Object>)) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorUnreadable', detail(null)));
		}
		Imported result = new Imported();
		result.kind = RECIPE;
		result.label = ConnectorRecipeDocument.textOf(file.get('name')).left(80);
		result.description = ConnectorRecipeDocument.textOf(file.get('description'));
		result.recipes.add(
			prepared(
				result.label,
				result.description,
				(Map<String, Object>) file.get('recipe'),
				ConnectorRecipeDocument.mapOf(file.get('names')),
				null
			)
		);
		return result;
	}

	private static Imported template(Map<String, Object> file) {
		refuseUnknown(file, TEMPLATE_KEYS);
		refuseNotYet(file, new List<String>{ 'pollers', 'webhook' });
		String label = ConnectorRecipeDocument.textOf(file.get('label'));
		if (
			file.get('version') != 1 ||
			!Pattern.matches('[a-z0-9-]{1,40}', ConnectorRecipeDocument.textOf(file.get('key'))) ||
			label.trim().length() < 1 ||
			label.length() > 80
		) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorUnreadable', detail(null)));
		}
		List<String> missing = new List<String>();
		for (Object name : ConnectorRecipeDocument.listOf(file.get('requires'))) {
			if (!objectExists(ConnectorRecipeDocument.textOf(name))) {
				missing.add(ConnectorRecipeDocument.textOf(name));
			}
		}
		if (!missing.isEmpty()) {
			throw refusal(
				BarnHelp.text('Connector', 'Connector_Import_ErrorMissing', detail(String.join(missing, ', ')))
			);
		}
		Imported result = new Imported();
		result.kind = TEMPLATE;
		result.label = label.trim();
		result.description = ConnectorRecipeDocument.textOf(file.get('description'));
		result.connection = prefill(file, result.label);
		Map<String, Map<String, Object>> actions = actions(file);
		List<Object> recipes = ConnectorRecipeDocument.listOf(file.get('recipes'));
		if (recipes.size() > MAX_TEMPLATE_RECIPES) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorUnreadable', detail(null)));
		}
		for (Object raw : recipes) {
			Map<String, Object> recipe = ConnectorRecipeDocument.mapOf(raw);
			refuseUnknown(recipe, TEMPLATE_RECIPE_KEYS);
			if (!(recipe.get('draft') instanceof Map<String, Object>)) {
				throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorUnreadable', detail(null)));
			}
			result.recipes.add(
				prepared(
					ConnectorRecipeDocument.textOf(recipe.get('name')).left(80),
					ConnectorRecipeDocument.textOf(recipe.get('description')),
					(Map<String, Object>) recipe.get('draft'),
					new Map<String, Object>(),
					actions
				)
			);
		}
		return result;
	}

	/** The template's connection: a built-in auth kind, an `https` base URL locked to its host (F1, F4). */
	private static Prefill prefill(Map<String, Object> file, String label) {
		Map<String, Object> auth = ConnectorRecipeDocument.mapOf(file.get('auth'));
		refuseUnknown(auth, AUTH_KEYS);
		Prefill result = new Prefill();
		result.label = label;
		result.authKind = ConnectorRecipeDocument.textOf(auth.get('kind'));
		if (!ConnectorConnections.KINDS.contains(result.authKind)) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorAuth', detail(result.authKind)));
		}
		for (Object raw : ConnectorRecipeDocument.listOf(auth.get('params'))) {
			refuseUnknown(ConnectorRecipeDocument.mapOf(raw), PARAM_KEYS);
		}
		if (result.authKind == ConnectorConnections.API_KEY) {
			result.headerName = ConnectorRecipeDocument.textOf(auth.get('headerName'));
			if (!ConnectorRecipeDocument.headerNameOk(result.headerName)) {
				throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorAuth', detail(result.headerName)));
			}
		}
		Map<String, UrlParam> params = new Map<String, UrlParam>();
		for (Object raw : ConnectorRecipeDocument.listOf(file.get('urlParams'))) {
			Map<String, Object> entry = ConnectorRecipeDocument.mapOf(raw);
			refuseUnknown(entry, PARAM_KEYS);
			UrlParam param = new UrlParam();
			param.name = ConnectorRecipeDocument.textOf(entry.get('name'));
			param.label = ConnectorRecipeDocument.textOf(entry.get('label'));
			param.help = ConnectorRecipeDocument.textOf(entry.get('help'));
			param.pattern = ConnectorRecipeDocument.textOf(entry.get('pattern'));
			param.fromParam = ConnectorRecipeDocument.textOf(entry.get('fromParam'));
			param.after = ConnectorRecipeDocument.textOf(entry.get('after')).left(1);
			if (String.isBlank(param.pattern) || param.pattern.length() > 100 || !compiles(param.pattern)) {
				throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorParam', detail(param.name)));
			}
			params.put(param.name, param);
		}
		result.baseUrl = ConnectorRecipeDocument.textOf(file.get('baseUrl')).trim().removeEnd('/');
		if (result.authKind != ConnectorConnections.SECRET_URL || String.isNotBlank(result.baseUrl)) {
			urlProblem(result.baseUrl, params);
		}
		result.urlParams = params.values();
		Map<String, Object> check = ConnectorRecipeDocument.mapOf(file.get('check'));
		refuseUnknown(check, new Set<String>{ 'method', 'path' });
		if (
			!check.isEmpty() &&
			(ConnectorRecipeDocument.textOf(check.get('method')) != 'GET' ||
			ConnectorRecipeDocument.pathProblem(ConnectorRecipeDocument.textOf(check.get('path'))))
		) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorAction', detail('check')));
		}
		result.checkPath = check.isEmpty() ? null : ConnectorRecipeDocument.textOf(check.get('path'));
		return result;
	}

	/**
	 * Refuses a template part BarnCRM does not import yet (pollers, a webhook, action inputs or
	 * body), so the author is told instead of the part being dropped.
	 */
	private static void refuseNotYet(Map<String, Object> source, List<String> parts) {
		for (String part : parts) {
			Object given = source.get(part);
			Boolean empty =
				given == null ||
				(given instanceof List<Object> && ((List<Object>) given).isEmpty()) ||
				(given instanceof Map<String, Object> && ((Map<String, Object>) given).isEmpty());
			if (!empty) {
				throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorNotYet', detail(part)));
			}
		}
	}

	/**
	 * A template's entry values (query, path values, headers): `{{watermark}}` in an App Poll
	 * trigger becomes the value path `trigger.watermark`; any other `{{...}}` is refused, since
	 * nothing would fill it.
	 */
	private static void templateValues(List<Object> entries, Boolean pollTrigger) {
		for (Object raw : entries) {
			Map<String, Object> entry = ConnectorRecipeDocument.mapOf(raw);
			String value = ConnectorRecipeDocument.textOf(entry.get('value'));
			if (!value.contains('{{')) {
				continue;
			}
			if (pollTrigger && value.trim() == '{{watermark}}') {
				entry.remove('value');
				entry.put('path', ConnectorAppPoll.WATERMARK_PATH);
			} else {
				throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorNotYet', detail(value)));
			}
		}
	}

	/** An `https` base URL whose placeholders sit in the host and each have a pattern (F4). */
	private static void urlProblem(String url, Map<String, UrlParam> params) {
		if (!BASE_URL.matcher(url).matches()) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorUrl', detail(url)));
		}
		String host = url.removeStart('https://').substringBefore('/');
		String rest = url.removeStart('https://').removeStart(host);
		Matcher slot = PLACEHOLDER.matcher(url);
		while (slot.find()) {
			if (!params.containsKey(slot.group(1))) {
				throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorParam', detail(slot.group(1))));
			}
		}
		if (rest.contains('{') || rest.contains('}')) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorUrl', detail(url)));
		}
		ConnectorConnections.checkedUrl(PLACEHOLDER.matcher(url).replaceAll('x'));
	}

	private static Map<String, Map<String, Object>> actions(Map<String, Object> file) {
		Map<String, Map<String, Object>> found = new Map<String, Map<String, Object>>();
		for (Object raw : ConnectorRecipeDocument.listOf(file.get('actions'))) {
			Map<String, Object> action = ConnectorRecipeDocument.mapOf(raw);
			refuseUnknown(action, ACTION_KEYS);
			refuseNotYet(action, new List<String>{ 'inputs', 'body' });
			String key = ConnectorRecipeDocument.textOf(action.get('key'));
			if (
				String.isBlank(key) ||
				!ConnectorRecipeDocument.METHODS.contains(ConnectorRecipeDocument.textOf(action.get('method'))) ||
				ConnectorRecipeDocument.pathProblem(ConnectorRecipeDocument.textOf(action.get('path')))
			) {
				throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorAction', detail(key)));
			}
			found.put(key, action);
		}
		return found;
	}

	// ---------------------------------------------------------------------------------------
	// One recipe: matched to this org, checked as Save and Publish (R-CR13)
	// ---------------------------------------------------------------------------------------

	/**
	 * A recipe document with its maps, import templates and connections matched by name to this
	 * org's, a template's actions copied into its steps, and each blank listed in the step's
	 * `fill`. Refused when it has a problem other than a blank; what Publish would still refuse
	 * is listed.
	 */
	private static Draft prepared(
		String name,
		String description,
		Map<String, Object> document,
		Map<String, Object> names,
		Map<String, Map<String, Object>> actions
	) {
		Matches matches = new Matches(names.values());
		Map<String, Object> starter = ConnectorRecipeDocument.mapOf(document.get('trigger'));
		starter.remove('savedQuery');
		Set<String> expected = new Set<String>();
		Draft result = new Draft();
		result.name = name;
		result.description = description;
		if (actions != null) {
			for (String entries : new List<String>{ 'query', 'pathValues' }) {
				templateValues(
					ConnectorRecipeDocument.listOf(starter.get(entries)),
					starter.get('kind') == ConnectorAppPoll.KIND
				);
			}
		}
		if (starter.get('kind') == ConnectorAppPoll.KIND && triggerBlanked(starter, names, matches)) {
			result.blanks.add('trigger');
			String problem = ConnectorTriggers.problem(starter);
			if (problem != null) {
				expected.add(problem);
			}
		}
		for (Map<String, Object> step : ConnectorRecipeDocument.allSteps(document)) {
			step.remove('savedQuery');
			if (actions != null) {
				copyAction(step, actions);
				for (String entries : new List<String>{ 'query', 'pathValues', 'headers' }) {
					templateValues(ConnectorRecipeDocument.listOf(step.get(entries)), false);
				}
			}
			for (String key : new List<String>{ 'map', 'bodyMap', 'template' }) {
				String given = ConnectorRecipeDocument.textOf(step.get(key));
				if (String.isNotBlank(given)) {
					String found = matches.byName.get(ConnectorRecipeDocument.textOf(names.get(given)));
					step.put(key, found == null ? '' : found);
					if (found == null) {
						addFill(step, key);
					}
				}
			}
			if (ConnectorRecipeDocument.CALL_KINDS.contains(ConnectorRecipeDocument.textOf(step.get('kind')))) {
				String found = matches.connectionByLabel.get(
					ConnectorRecipeDocument.textOf(names.get(ConnectorRecipeDocument.textOf(step.get('connection'))))
				);
				step.put('connection', found == null ? '' : found);
				if (found == null) {
					addFill(step, 'connection');
				}
			}
			List<Object> at = new List<Object>{ ConnectorRecipeDocument.textOf(step.get('id')) };
			Set<String> blanks = new Set<String>();
			for (Object key : ConnectorRecipeDocument.listOf(step.get('fill'))) {
				blanks.add(String.valueOf(key));
			}
			if (!blanks.isEmpty()) {
				result.blanks.add(String.valueOf(at[0]));
				expected.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorFill', at));
			}
			expected.addAll(blankProblems(blanks, at));
		}
		String text = JSON.serialize(document);
		ConnectorRecipeDocument.parse(text);
		List<String> refused = new List<String>();
		for (String problem : ConnectorRecipeDocument.problems(document)) {
			if (!expected.contains(problem)) {
				refused.add(problem);
			}
		}
		if (!refused.isEmpty()) {
			throw refusal(
				BarnHelp.text(
					'Connector',
					'Connector_Import_ErrorRecipe',
					detail(name + ': ' + String.join(refused, ' '))
				)
			);
		}
		List<String> later;
		try {
			later = ConnectorRecipes.publishProblems(document, ConnectorRecipes.RUN_AS_AUTOMATION);
		} catch (Exception notReady) {
			later = new List<String>{ notReady.getMessage() };
		}
		for (String problem : later) {
			if (!expected.contains(problem)) {
				result.problems.add(problem);
			}
		}
		result.draftJson = text;
		return result;
	}

	/**
	 * An App Poll trigger's connection matched by label (blank when this org has none), and
	 * whether the import left it or a sign-in header value blank for the admin to fill.
	 */
	private static Boolean triggerBlanked(Map<String, Object> starter, Map<String, Object> names, Matches matches) {
		String found = matches.connectionByLabel.get(
			ConnectorRecipeDocument.textOf(names.get(ConnectorRecipeDocument.textOf(starter.get('connection'))))
		);
		starter.put('connection', found == null ? '' : found);
		Boolean blanked = found == null;
		for (Object raw : ConnectorRecipeDocument.listOf(starter.get('headers'))) {
			Map<String, Object> header = ConnectorRecipeDocument.mapOf(raw);
			blanked |=
				ConnectorRecipeDocument.SIGN_IN_HEADER.matcher(ConnectorRecipeDocument.textOf(header.get('name')))
					.matches() &&
				String.isBlank(ConnectorRecipeDocument.textOf(header.get('path'))) &&
				String.isBlank(ConnectorRecipeDocument.textOf(header.get('value')));
		}
		return blanked;
	}

	/** The problems Save reports for the keys an import left blank, which the editor fills. */
	private static Set<String> blankProblems(Set<String> blanks, List<Object> at) {
		Set<String> found = new Set<String>();
		for (String blank : blanks) {
			switch on blank {
				when 'connection' {
					found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorConnection', at));
				}
				when 'map', 'bodyMap' {
					found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorMap', at));
				}
				when 'template' {
					found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorTemplate', at));
				}
				when 'pathValues' {
					found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorSlot', at));
				}
			}
		}
		return found;
	}

	/**
	 * A template action named by a Call an App step: its method, path and query, each slot blank.
	 * Its query values are checked by `templateValues` after the copy.
	 */
	private static void copyAction(Map<String, Object> step, Map<String, Map<String, Object>> actions) {
		if (step.get('kind') != 'callApp' || !step.containsKey('action')) {
			return;
		}
		Map<String, Object> action = actions.get(ConnectorRecipeDocument.textOf(step.remove('action')));
		if (action == null) {
			throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorAction', detail(step.get('id'))));
		}
		String path = ConnectorRecipeDocument.textOf(action.get('path'));
		step.put('method', action.get('method'));
		step.put('path', path);
		List<Object> query = new List<Object>();
		Map<String, Object> given = ConnectorRecipeDocument.mapOf(action.get('query'));
		for (String key : given.keySet()) {
			query.add(
				new Map<String, Object>{ 'name' => key, 'value' => ConnectorRecipeDocument.textOf(given.get(key)) }
			);
		}
		step.put('query', query);
		List<Object> slots = new List<Object>();
		Matcher slot = PLACEHOLDER.matcher(path);
		while (slot.find()) {
			slots.add(new Map<String, Object>{ 'name' => slot.group(1), 'path' => '' });
		}
		step.put('pathValues', slots);
		if (!slots.isEmpty()) {
			addFill(step, 'pathValues');
		}
	}

	/** This org's maps and import templates by name, and connections by label, for the names a file gives. */
	private inherited sharing class Matches {
		Map<String, String> byName = new Map<String, String>();
		Map<String, String> connectionByLabel = new Map<String, String>();

		Matches(List<Object> given) {
			Set<String> wanted = new Set<String>();
			for (Object name : given) {
				wanted.add(ConnectorRecipeDocument.textOf(name));
			}
			if (wanted.isEmpty()) {
				return;
			}
			for (Saved_Transform__c saved : [
				SELECT Id, Name
				FROM Saved_Transform__c
				WHERE Name IN :wanted AND Kind__c = :ConnectorMapRuntime.KIND_MAP
				WITH USER_MODE
				LIMIT 500
			]) {
				byName.put(saved.Name, saved.Id);
			}
			if (Schema.SObjectType.Import_Template__c.isAccessible()) {
				for (Import_Template__c template : ImportTemplateSelector.selectActive()) {
					if (wanted.contains(template.Name) && !byName.containsKey(template.Name)) {
						byName.put(template.Name, template.Id);
					}
				}
			}
			for (ConnectorConnections.Connection connection : ConnectorConnections.page().connections) {
				if (wanted.contains(connection.label)) {
					connectionByLabel.put(connection.label, connection.name);
				}
			}
		}
	}

	// ---------------------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------------------

	private static void addFill(Map<String, Object> step, String key) {
		List<Object> fill = new List<Object>(ConnectorRecipeDocument.listOf(step.get('fill')));
		if (!fill.contains(key)) {
			fill.add(key);
		}
		step.put('fill', fill);
	}

	private static void refuseUnknown(Map<String, Object> entries, Set<String> allowed) {
		for (String key : entries.keySet()) {
			if (!allowed.contains(key)) {
				throw refusal(BarnHelp.text('Connector', 'Connector_Import_ErrorKey', detail(key)));
			}
		}
	}

	private static Boolean compiles(String expression) {
		try {
			Pattern.compile(expression);
			return true;
		} catch (Exception invalid) {
			return false;
		}
	}

	/** Whether this org has an object a template's recipes need. */
	private static Boolean objectExists(String name) {
		if (!Pattern.matches('[A-Za-z0-9_]{1,80}', name)) {
			return false;
		}
		try {
			return !Schema.describeSObjects(new List<String>{ name }).isEmpty();
		} catch (Exception missing) {
			return false;
		}
	}

	private static FileException refusal(String text) {
		return new FileException(text);
	}

	/** The one value a refusal names, cut short so a file cannot fill the message. */
	private static List<Object> detail(Object value) {
		return new List<Object>{ value == null ? '' : String.valueOf(value).left(80) };
	}
}
