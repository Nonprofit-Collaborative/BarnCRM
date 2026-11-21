/**
 * Load Rows with an Import Template (CN-09, C-38; canonical model R-CR9, R-IB18; design Section
 * 3.4): an unattended import that commits only inside the limits the admin set on the step.
 *
 * Nothing here imports anything itself. The rows go to Super Importer's own staging through
 * Core's `ImportBatchService` (create, stage, dry run, commit), so matching, transforms, lookups,
 * rejections, the journal and Undo are exactly those of an upload. The step waits while a pass
 * runs (the run is Waiting and the recipe clock wakes it every 5 minutes), reads the dry run's
 * counts, and commits only when every count is inside its limit. Outside a limit, nothing is
 * committed: the data job stays a finished dry run in Super Importer for a person to check, and
 * the run fails, saying which limit and which job.
 *
 * Core's staging, dry run and commit write in user mode as the running user, so the recipe's
 * identity needs the Manage BarnCRM Settings permission that Super Importer asks of a person,
 * whatever the recipe's access mode.
 */
public inherited sharing class ConnectorImportStep {
	/** The most rows one step stages: one write of the rows, and one of their keys, in a transaction. */
	public static final Integer MOST_ROWS = 4000;
	public static final List<String> LIMIT_KEYS = new List<String>{ 'rows', 'rejected', 'created', 'updated' };
	public static final Map<String, Integer> DEFAULTS = new Map<String, Integer>{
		'rows' => 1000,
		'rejected' => 0,
		'created' => 1000,
		'updated' => 1000
	};
	/** Minutes between looks at a running pass: the recipe clock's beat. */
	public static final Integer WAIT_MINUTES = 5;
	/** A pass still running after this many hours fails the step. */
	public static final Integer MOST_HOURS = 24;
	private static final String DRY_RUN = 'dryRun';
	private static final String COMMITTING = 'commit';

	/** What is wrong with the step's template, rows path or limits, in words naming it, or null. */
	public static String problem(Map<String, Object> step, List<Object> at) {
		if (!ConnectorRecipeDocument.isId(ConnectorRecipeDocument.textOf(step.get('template')))) {
			return BarnHelp.text('Connector', 'Connector_Recipe_ErrorTemplate', at);
		}
		if (!ConnectorRecipeDocument.isPath(ConnectorRecipeDocument.textOf(step.get('rows')))) {
			return BarnHelp.text('Connector', 'Connector_Recipe_ErrorPath', at);
		}
		Map<String, Object> given = ConnectorRecipeDocument.mapOf(step.get('limits'));
		for (String key : LIMIT_KEYS) {
			Object value = given.get(key);
			Boolean bad =
				value != null &&
				(!(value instanceof Integer) ||
				(Integer) value < (key == 'rows' ? 1 : 0) ||
				(Integer) value > MOST_ROWS);
			if (bad) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorLimits', at);
			}
		}
		return null;
	}

	/** A limit as set on the step, or its default when blank. */
	public static Integer limitOf(Map<String, Object> step, String key) {
		Object value = ConnectorRecipeDocument.mapOf(step.get('limits')).get(key);
		return value instanceof Integer ? (Integer) value : DEFAULTS.get(key);
	}

	/**
	 * Starts or continues the step. The first call stages the rows and starts the dry run; each
	 * later call, with the progress kept in the run's State, looks at the pass and either waits
	 * again, commits, or finishes with the counts. A Test run only reads the rows and says what it
	 * would load.
	 */
	public static Map<String, Object> perform(
		Map<String, Object> step,
		Object source,
		Map<String, Object> progress,
		Connector_Run__c run,
		ConnectorStepRunner.Budget budget
	) {
		if (!BarnCRMPermissions.canManageSettings()) {
			throw failure(BarnHelp.text('Connector', 'Connector_Import_ErrorPermission', new List<Object>()));
		}
		try {
			if (progress.get('batchId') == null) {
				return start(step, source, run, budget);
			}
			return proceed(step, progress, budget);
		} catch (ImportException refused) {
			// Core's own words, written for a person.
			throw new ConnectorStepRunner.StepFailureException(refused.getMessage());
		}
	}

	private static Map<String, Object> start(
		Map<String, Object> step,
		Object source,
		Connector_Run__c run,
		ConnectorStepRunner.Budget budget
	) {
		List<Map<String, Object>> rows = rowsOf(source);
		Integer most = limitOf(step, 'rows');
		if (rows.size() > most) {
			throw failure(
				BarnHelp.text('Connector', 'Connector_Import_ErrorTooManyRows', new List<Object>{ rows.size(), most })
			);
		}
		Import_Template__c template = ImportTemplateSelector.selectById(
			Id.valueOf(ConnectorRecipeDocument.textOf(step.get('template')))
		);
		if (template == null || template.Active__c != true) {
			throw failure(BarnHelp.text('Connector', 'Connector_Import_ErrorTemplateGone', new List<Object>()));
		}
		if (run.Is_Test__c == true) {
			Map<String, Object> chosen = new Map<String, Object>();
			for (String key : LIMIT_KEYS) {
				chosen.put(key, limitOf(step, key));
			}
			return new Map<String, Object>{
				'rows' => rows.size(),
				'wouldWrite' => new Map<String, Object>{
					'template' => template.Name,
					'rows' => rows.size(),
					'limits' => chosen
				}
			};
		}
		if (rows.isEmpty()) {
			return new Map<String, Object>{
				'rows' => 0,
				'created' => 0,
				'updated' => 0,
				'rejected' => 0,
				'summary' => BarnHelp.text('Connector', 'Connector_Import_NoRows')
			};
		}
		Import_Batch__c batch = ImportBatchService.create(
			template.Id,
			null,
			BarnHelp.text('Connector', 'Connector_Import_FileName', new List<Object>{ run.Recipe__r.Name, run.Name }),
			null,
			null,
			null,
			false
		);
		// The header is file row 1, as for an uploaded file.
		ImportBatchService.stageRows(batch.Id, rows, 2);
		ImportBatchService.startDryRun(batch.Id);
		budget.wrote = true;
		throw waiting(new Map<String, Object>{ 'batchId' => batch.Id, 'phase' => DRY_RUN, 'since' => now() });
	}

	private static Map<String, Object> proceed(
		Map<String, Object> step,
		Map<String, Object> progress,
		ConnectorStepRunner.Budget budget
	) {
		Import_Batch__c batch = ImportBatchSelector.selectById(
			Id.valueOf(ConnectorRecipeDocument.textOf(progress.get('batchId')))
		);
		if (batch == null) {
			throw failure(BarnHelp.text('Connector', 'Connector_Import_ErrorBatchGone', new List<Object>()));
		}
		Long since = Long.valueOf(ConnectorRecipeDocument.textOf(progress.get('since')));
		if (ImportBatchService.isRunning(batch)) {
			if (now() - since > MOST_HOURS * 3600000L) {
				throw failure(
					BarnHelp.text('Connector', 'Connector_Import_ErrorTooLong', new List<Object>{ batch.Name })
				);
			}
			throw waiting(progress);
		}
		if (ConnectorRecipeDocument.textOf(progress.get('phase')) == DRY_RUN) {
			if (batch.Status__c != ImportBatchService.STATUS_DRY_RUN_COMPLETE) {
				throw failure(
					BarnHelp.text(
						'Connector',
						'Connector_Import_ErrorDryRun',
						new List<Object>{ batch.Name, batch.Status__c }
					)
				);
			}
			String over = overLimit(step, batch);
			if (over != null) {
				throw new ConnectorStepRunner.StepFailureException(over);
			}
			ImportBatchService.startCommit(batch.Id);
			budget.wrote = true;
			throw waiting(new Map<String, Object>{ 'batchId' => batch.Id, 'phase' => COMMITTING, 'since' => now() });
		}
		if (batch.Status__c != ImportBatchService.STATUS_COMPLETE) {
			throw failure(
				BarnHelp.text(
					'Connector',
					'Connector_Import_ErrorCommit',
					new List<Object>{ batch.Name, batch.Status__c }
				)
			);
		}
		Map<String, Object> counts = counts(batch);
		counts.put('batchId', batch.Id);
		counts.put('batch', batch.Name);
		counts.put(
			'summary',
			BarnHelp.text(
				'Connector',
				'Connector_Import_Loaded',
				new List<Object>{
					batch.Name,
					counts.get('rows'),
					counts.get('created'),
					counts.get('updated'),
					counts.get('rejected')
				}
			)
		);
		return counts;
	}

	/** The first count of a finished dry run that is over its limit, in words, or null. */
	@TestVisible
	private static String overLimit(Map<String, Object> step, Import_Batch__c batch) {
		Map<String, Object> counts = counts(batch);
		for (String key : new List<String>{ 'rejected', 'created', 'updated' }) {
			Integer found = (Integer) counts.get(key);
			Integer most = limitOf(step, key);
			if (found > most) {
				List<Object> values = new List<Object>{ found };
				String what = key == 'rejected'
					? BarnHelp.text('Connector', 'Connector_Import_OverRejected', values)
					: key == 'created'
							? BarnHelp.text('Connector', 'Connector_Import_OverCreated', values)
							: BarnHelp.text('Connector', 'Connector_Import_OverUpdated', values);
				return BarnHelp.text(
					'Connector',
					'Connector_Import_ErrorOverLimit',
					new List<Object>{ batch.Name, what, most }
				);
			}
		}
		return null;
	}

	private static Map<String, Object> counts(Import_Batch__c batch) {
		return new Map<String, Object>{
			'rows' => whole(batch.Row_Count__c),
			'created' => whole(batch.Rows_Created__c),
			'updated' => whole(batch.Rows_Updated__c),
			'matched' => whole(batch.Rows_Matched__c),
			'rejected' => whole(batch.Rows_Rejected__c)
		};
	}

	/** Records the step wrote, for the run's Records Written. */
	public static Integer written(Map<String, Object> result) {
		Object created = result.get('created');
		Object updated = result.get('updated');
		return (created instanceof Integer ? (Integer) created : 0) +
			(updated instanceof Integer ? (Integer) updated : 0);
	}

	// ---------------------------------------------------------------------------------------
	// Reading rows
	// ---------------------------------------------------------------------------------------

	/**
	 * Rows keyed by column name, from a list of objects, a list of lists whose first list holds
	 * the column names (a Google Sheets range), or CSV text with a header row. Values are text,
	 * as a file's are; a nested value is kept as its JSON.
	 */
	@TestVisible
	private static List<Map<String, Object>> rowsOf(Object source) {
		if (source == null) {
			return new List<Map<String, Object>>();
		}
		if (source instanceof String) {
			return fromLists(csv((String) source));
		}
		if (!(source instanceof List<Object>)) {
			throw failure(BarnHelp.text('Connector', 'Connector_Import_ErrorRowsUnreadable', new List<Object>()));
		}
		List<Object> items = (List<Object>) source;
		if (items.isEmpty() || items[0] instanceof List<Object>) {
			return fromLists(items);
		}
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		for (Object item : items) {
			if (!(item instanceof Map<String, Object>)) {
				throw failure(BarnHelp.text('Connector', 'Connector_Import_ErrorRowsUnreadable', new List<Object>()));
			}
			Map<String, Object> row = new Map<String, Object>();
			Map<String, Object> given = (Map<String, Object>) item;
			for (String column : given.keySet()) {
				row.put(column, textOf(given.get(column)));
			}
			rows.add(row);
		}
		return rows;
	}

	private static List<Map<String, Object>> fromLists(List<Object> lines) {
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		if (lines.isEmpty()) {
			return rows;
		}
		List<String> header = new List<String>();
		for (Object cell : listOf(lines[0])) {
			header.add(textOf(cell) == null ? '' : textOf(cell).trim());
		}
		for (Integer i = 1; i < lines.size(); i++) {
			List<Object> cells = listOf(lines[i]);
			Map<String, Object> row = new Map<String, Object>();
			for (Integer c = 0; c < header.size(); c++) {
				if (String.isNotBlank(header[c])) {
					row.put(header[c], c < cells.size() ? textOf(cells[c]) : null);
				}
			}
			rows.add(row);
		}
		return rows;
	}

	/**
	 * CSV text (RFC 4180: quoted fields, doubled quotes, commas and line breaks inside quotes) as
	 * lines of cells. Each run of plain characters is taken with one `substring`, so a long cell
	 * costs one copy, not one per character.
	 */
	@TestVisible
	private static List<Object> csv(String text) {
		final Integer quote = 34;
		final Integer comma = 44;
		final Integer lineFeed = 10;
		final Integer carriageReturn = 13;
		List<Object> lines = new List<Object>();
		List<Object> cells = new List<Object>();
		String cell = '';
		Boolean quoted = false;
		Integer start = 0;
		Integer i = 0;
		Integer size = text.length();
		while (i < size) {
			Integer c = text.charAt(i);
			if (quoted) {
				if (c == quote) {
					cell += text.substring(start, i);
					if (i + 1 < size && text.charAt(i + 1) == quote) {
						cell += '"';
						i++;
					} else {
						quoted = false;
					}
					start = i + 1;
				}
			} else if (c == quote) {
				cell += text.substring(start, i);
				quoted = true;
				start = i + 1;
			} else if (c == comma) {
				cells.add(cell + text.substring(start, i));
				cell = '';
				start = i + 1;
			} else if (c == lineFeed || c == carriageReturn) {
				cells.add(cell + text.substring(start, i));
				if (c == carriageReturn && i + 1 < size && text.charAt(i + 1) == lineFeed) {
					i++;
				}
				lines.add(cells);
				cells = new List<Object>();
				cell = '';
				start = i + 1;
			}
			i++;
		}
		if (quoted) {
			throw failure(BarnHelp.text('Connector', 'Connector_Import_ErrorRowsUnreadable', new List<Object>()));
		}
		cell += text.substring(start, size);
		if (cell != '' || !cells.isEmpty()) {
			cells.add(cell);
			lines.add(cells);
		}
		return lines;
	}

	private static List<Object> listOf(Object raw) {
		if (!(raw instanceof List<Object>)) {
			throw failure(BarnHelp.text('Connector', 'Connector_Import_ErrorRowsUnreadable', new List<Object>()));
		}
		return (List<Object>) raw;
	}

	private static String textOf(Object value) {
		if (value == null) {
			return null;
		}
		return value instanceof Map<String, Object> || value instanceof List<Object>
			? JSON.serialize(value)
			: String.valueOf(value);
	}

	// ---------------------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------------------

	private static Integer whole(Decimal value) {
		return value == null ? 0 : value.intValue();
	}

	private static Long now() {
		return Datetime.now().getTime();
	}

	private static ConnectorStepRunner.WaitException waiting(Map<String, Object> progress) {
		ConnectorStepRunner.WaitException wait = new ConnectorStepRunner.WaitException();
		wait.progress = progress;
		wait.minutes = WAIT_MINUTES;
		return wait;
	}

	private static ConnectorStepRunner.StepFailureException failure(String text) {
		return new ConnectorStepRunner.StepFailureException(text);
	}
}
