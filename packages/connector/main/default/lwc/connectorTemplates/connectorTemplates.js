import { LightningElement } from 'lwc';
import importFile from '@salesforce/apex/ConnectorRecipesController.importFile';
import { fileProblem } from 'c/connectorFileRules';
import { kindKey } from 'c/connectorRules';
import { say as text } from 'c/connectorRecipeText';
import { say as connectionText } from 'c/connectorText';

/**
 * The Templates tab of Super Connector (CN-08, D-216; canonical model R-CR11 to R-CR13): imports
 * a template or an exported recipe from a file or pasted text. The file is checked here
 * (c/connectorFileRules) and again in Apex, which matches it to this org and checks it as Save
 * and Publish would. Nothing is stored: the page offers a New Connection form filled in
 * (`connection` event, never a key) and each recipe as an unsaved draft (`opendraft` event).
 */
export default class ConnectorTemplates extends LightningElement {
  pasted = '';
  fileText;
  imported;
  working = false;
  error;

  labels = {
    get heading() {
      return text('Connector_Templates_Heading');
    },
    get intro() {
      return text('Connector_Templates_Intro');
    },
    get chooseFile() {
      return text('Connector_Templates_ChooseFile');
    },
    get paste() {
      return text('Connector_Templates_Paste');
    },
    get pasteHelp() {
      return text('Connector_Templates_PasteHelp');
    },
    get importButton() {
      return text('Connector_Templates_Import');
    },
    get nothingKept() {
      return text('Connector_Templates_NothingKept');
    },
    get connectionHeading() {
      return text('Connector_Templates_Connection');
    },
    get createConnection() {
      return text('Connector_Templates_CreateConnection');
    },
    get recipesHeading() {
      return text('Connector_Templates_Recipes');
    },
    get noRecipes() {
      return text('Connector_Templates_NoRecipes');
    },
    get beforePublish() {
      return text('Connector_Templates_BeforePublish');
    },
    get openDraft() {
      return text('Connector_Templates_OpenDraft');
    }
  };

  get importedHeading() {
    if (!this.imported) {
      return '';
    }
    return text(
      this.imported.kind === 'template'
        ? 'Connector_Templates_TemplateHeading'
        : 'Connector_Templates_RecipeHeading',
      this.imported.label
    );
  }

  get connection() {
    return this.imported && this.imported.connection;
  }

  get connectionDetail() {
    const connection = this.connection;
    return connection
      ? text(
          'Connector_Templates_ConnectionDetail',
          connection.label,
          connectionText(kindKey(connection.authKind)),
          connection.baseUrl || ''
        )
      : '';
  }

  get recipeRows() {
    return ((this.imported && this.imported.recipes) || []).map((recipe, index) => ({
      key: `recipe-${index}`,
      index,
      name: recipe.name,
      blanksText: (recipe.blanks || []).length
        ? text('Connector_Templates_Blanks', recipe.blanks.join(', '))
        : '',
      problemsText: (recipe.problems || []).join(' '),
      openId: `open-draft-${index}`,
      openLabel: text('Connector_Templates_OpenNamed', recipe.name)
    }));
  }

  get noRecipes() {
    return !this.recipeRows.length;
  }

  handleFile(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) {
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      this.fileText = String(reader.result || '');
      this.pasted = '';
    };
    reader.readAsText(file);
  }

  handlePaste(event) {
    this.pasted = event.target.value;
    this.fileText = undefined;
  }

  async handleImport() {
    const source = this.fileText || this.pasted;
    this.error = undefined;
    this.imported = undefined;
    const problem = fileProblem(source);
    if (problem) {
      this.error = text(problem.key, problem.detail);
      return;
    }
    this.working = true;
    try {
      this.imported = await importFile({ fileText: source });
    } catch (failure) {
      this.error =
        (failure && failure.body && failure.body.message) || text('Connector_Error_Unexpected');
    } finally {
      this.working = false;
    }
  }

  handleConnection() {
    this.dispatchEvent(
      new CustomEvent('connection', { detail: { prefill: { ...this.connection } } })
    );
  }

  handleOpenDraft(event) {
    const recipe = this.imported.recipes[Number(event.target.dataset.index)];
    this.dispatchEvent(
      new CustomEvent('opendraft', {
        detail: {
          name: recipe.name,
          description: recipe.description,
          draftJson: recipe.draftJson
        }
      })
    );
  }
}
