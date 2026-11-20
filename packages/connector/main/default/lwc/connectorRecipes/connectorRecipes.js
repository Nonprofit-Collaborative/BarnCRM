import { LightningElement, api } from 'lwc';
import getRecipes from '@salesforce/apex/ConnectorRecipesController.getRecipes';
import getRecipeAccess from '@salesforce/apex/ConnectorRecipesController.getRecipeAccess';
import saveRecipeAccess from '@salesforce/apex/ConnectorRecipesController.saveRecipeAccess';
import { statusVariant } from 'c/connectorRecipeRules';
import { say as text } from 'c/connectorRecipeText';

/**
 * The Recipes tab of Super Connector (CN-02; canonical model R-CR1 to R-CR4): the recipes with
 * their status, Run As and version, New Recipe, the editor for the one opened, and Recipe Access
 * (the permission sets BarnCRM Automation recipes run with). Viewers see the list only.
 */
export default class ConnectorRecipes extends LightningElement {
  /** A recipe Id to open, from the page state (a Where Used link); it may arrive after load. */
  @api
  get openRecipeId() {
    return this.requestedId;
  }
  set openRecipeId(value) {
    this.requestedId = value;
    if (value) {
      this.creating = false;
      this.selectedId = value;
    }
  }

  requestedId;
  page;
  selectedId;
  creating = false;
  access;
  accessOpen = false;
  picked = [];
  working = false;
  message;
  error;

  labels = {
    get heading() {
      return text('Connector_Recipes_Heading');
    },
    get intro() {
      return text('Connector_Recipes_Intro');
    },
    get newRecipe() {
      return text('Connector_Recipes_New');
    },
    get empty() {
      return text('Connector_Recipes_Empty');
    },
    get open() {
      return text('Connector_Recipes_Open');
    },
    get accessButton() {
      return text('Connector_Access_Heading');
    },
    get accessHeading() {
      return text('Connector_Access_Heading');
    },
    get accessIntro() {
      return text('Connector_Access_Intro');
    },
    get accessSets() {
      return text('Connector_Access_Sets');
    },
    get accessSave() {
      return text('Connector_Access_Save');
    },
    get accessNotSaved() {
      return text('Connector_Access_NotSaved');
    },
    get accessNotReady() {
      return text('Connector_Access_NotReady');
    },
    get cancel() {
      return text('Connector_Editor_Close');
    },
    get loading() {
      return text('Connector_Recipes_Heading');
    }
  };

  connectedCallback() {
    this.load();
  }

  async load() {
    this.error = undefined;
    try {
      this.page = (await getRecipes()) || { canManage: false, recipes: [] };
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  get loaded() {
    return Boolean(this.page);
  }

  get canManage() {
    return this.loaded && this.page.canManage === true;
  }

  get rows() {
    return ((this.page && this.page.recipes) || []).map((recipe) => ({
      ...recipe,
      statusLabel: text(`Connector_Status_${recipe.status}`) || recipe.status,
      statusVariant: statusVariant(recipe.status),
      detail: text(
        'Connector_Recipes_Detail',
        recipe.runAs === 'System'
          ? text('Connector_RunAs_System')
          : text('Connector_RunAs_Automation'),
        recipe.version
      ),
      showUnpublished: recipe.unpublished === true && recipe.status !== 'Draft',
      unpublishedLabel: text('Connector_Recipes_Unpublished'),
      openId: `open-${recipe.id}`,
      openLabel: text('Connector_Recipes_OpenNamed', recipe.name)
    }));
  }

  get empty() {
    return this.loaded && !this.rows.length && !this.editorOpen;
  }

  get editorOpen() {
    return this.creating || Boolean(this.selected);
  }

  get selected() {
    return this.selectedId ? this.rows.find((row) => row.id === this.selectedId) : undefined;
  }

  get listShown() {
    return this.loaded && !this.editorOpen;
  }

  handleNew() {
    this.clear();
    this.selectedId = undefined;
    this.creating = true;
  }

  handleOpen(event) {
    this.clear();
    this.creating = false;
    this.selectedId = event.target.dataset.recipe;
  }

  /** The editor saved, published, ran or deleted: reload, keeping the recipe open unless gone. */
  async handleChanged(event) {
    const detail = event.detail || {};
    await this.load();
    this.creating = false;
    this.selectedId = detail.deleted ? undefined : detail.recipeId || this.selectedId;
    this.message = detail.message;
  }

  handleClose() {
    this.creating = false;
    this.selectedId = undefined;
  }

  async handleAccessToggle() {
    this.clear();
    if (this.accessOpen) {
      this.accessOpen = false;
      return;
    }
    this.working = true;
    try {
      this.access = await getRecipeAccess();
      this.picked = ((this.access && this.access.choices) || [])
        .filter((choice) => choice.picked)
        .map((choice) => choice.id);
      this.accessOpen = true;
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  get accessOptions() {
    return ((this.access && this.access.choices) || []).map((choice) => ({
      label: choice.label,
      value: choice.id
    }));
  }

  get accessNotSavedShown() {
    return this.access && this.access.ready && !this.access.saved;
  }

  get accessNotReadyShown() {
    return this.access && !this.access.ready;
  }

  handlePicked(event) {
    this.picked = event.detail.value;
  }

  async handleAccessSave() {
    this.clear();
    this.working = true;
    try {
      this.access = await saveRecipeAccess({ permissionSetIds: this.picked });
      this.message = text('Connector_Access_Saved');
      this.accessOpen = false;
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  clear() {
    this.message = undefined;
    this.error = undefined;
  }

  messageOf(failure) {
    return (failure && failure.body && failure.body.message) || text('Connector_Error_Unexpected');
  }
}
