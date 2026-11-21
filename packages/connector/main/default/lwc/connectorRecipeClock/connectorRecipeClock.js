import { LightningElement } from 'lwc';
import getClock from '@salesforce/apex/ConnectorRecipesController.getClock';
import setRecipesPaused from '@salesforce/apex/ConnectorRecipesController.setRecipesPaused';
import restartClock from '@salesforce/apex/ConnectorRecipesController.restartClock';
import getIntegrationUser from '@salesforce/apex/ConnectorRecipesController.getIntegrationUser';
import chooseIntegrationUser from '@salesforce/apex/ConnectorRecipesController.chooseIntegrationUser';
import { say as text } from 'c/connectorRecipeText';

/**
 * Recipe Clock on the Recipes tab of Super Connector (CN-03; canonical model R-CR4, R-CR6,
 * R-CR7, R-CS1; design Sections 3.2 and 3.10). Each Run As lane with whether it has work and
 * whether its heartbeat is going, Pause All Recipes (org-wide), Restart Clock, and the integration
 * user: the user picker, Save User, its state, and the Setup step Salesforce leaves to a person
 * (Suspend and Resume the subscription). Connector admins only; the server checks every call.
 */
export default class ConnectorRecipeClock extends LightningElement {
  clock;
  user;
  pickedUserId;
  working = false;
  message;
  error;

  labels = {
    get heading() {
      return text('Connector_Clock_Heading');
    },
    get intro() {
      return text('Connector_Clock_Intro');
    },
    get pauseAll() {
      return text('Connector_Clock_PauseAll');
    },
    get pauseAllHelp() {
      return text('Connector_Clock_PauseAllHelp');
    },
    get pausedNotice() {
      return text('Connector_Clock_PausedNotice');
    },
    get automationPaused() {
      return text('Connector_Clock_AutomationPaused');
    },
    get restart() {
      return text('Connector_Clock_Restart');
    },
    get userHeading() {
      return text('Connector_User_Heading');
    },
    get userIntro() {
      return text('Connector_User_Intro');
    },
    get userPick() {
      return text('Connector_User_Pick');
    },
    get userSave() {
      return text('Connector_User_Save');
    },
    get userNone() {
      return text('Connector_User_None');
    },
    get userSteps() {
      return text('Connector_User_Steps');
    },
    get orgConnection() {
      return text('Connector_User_OrgConnection');
    },
    get working() {
      return text('Connector_Editor_Working');
    }
  };

  connectedCallback() {
    this.load();
  }

  async load() {
    this.working = true;
    try {
      const [clock, user] = await Promise.all([getClock(), getIntegrationUser()]);
      this.clock = clock;
      this.showUser(user);
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  showUser(user) {
    this.user = user || {};
    this.pickedUserId = this.user.id || undefined;
  }

  get loaded() {
    return Boolean(this.clock && this.user);
  }

  get paused() {
    return Boolean(this.clock && this.clock.paused);
  }

  get automationPausedShown() {
    return Boolean(this.clock && this.clock.automationPaused);
  }

  /** Each lane as a row: its name and a badge for Going, Stopped or No Work. */
  get lanes() {
    return ((this.clock && this.clock.lanes) || []).map((lane) => {
      let state = 'Idle';
      if (lane.beating) {
        state = 'Going';
      } else if (lane.needed) {
        state = 'Stopped';
      }
      return {
        key: lane.lane,
        name: text(`Connector_Lane_${lane.lane}`),
        state: text(`Connector_Clock_${state}`),
        tone: { Going: 'success', Stopped: 'warning', Idle: 'neutral' }[state],
        dataId: `lane-${lane.lane}`
      };
    });
  }

  get userNotices() {
    const user = this.user || {};
    const notices = [];
    if (!user.orgConnectionReady) {
      notices.push({ key: 'org', variant: 'warning', message: this.labels.orgConnection });
    }
    if (!user.id) {
      notices.push({ key: 'none', variant: 'info', message: this.labels.userNone });
    } else if (!user.active) {
      notices.push({
        key: 'inactive',
        variant: 'error',
        message: text('Connector_User_Inactive', user.name)
      });
    } else {
      if (!user.hasConnections) {
        notices.push({
          key: 'access',
          variant: 'warning',
          message: text('Connector_User_NoConnections', user.name)
        });
      }
      notices.push(
        user.confirmed
          ? {
              key: 'confirmed',
              variant: 'success',
              message: text('Connector_User_Confirmed', user.name)
            }
          : {
              key: 'pending',
              variant: 'info',
              message: text('Connector_User_NotConfirmed', user.name)
            }
      );
    }
    return notices;
  }

  get lastWrite() {
    return this.user && this.user.lastWrite
      ? text('Connector_User_LastWrite', this.user.lastWrite)
      : '';
  }

  get saveDisabled() {
    return this.working || !this.user || !this.user.orgConnectionReady;
  }

  handlePickUser(event) {
    this.pickedUserId = event.detail ? event.detail.recordId || undefined : undefined;
  }

  handlePauseAll(event) {
    const paused = event.target.checked;
    return this.work(async () => {
      this.clock = await setRecipesPaused({ paused });
      this.message = text(paused ? 'Connector_Clock_PausedOn' : 'Connector_Clock_PausedOff');
    });
  }

  handleRestart() {
    return this.work(async () => {
      this.clock = await restartClock();
      this.message = text('Connector_Clock_Restarted');
    });
  }

  handleSaveUser() {
    return this.work(async () => {
      this.showUser(await chooseIntegrationUser({ userId: this.pickedUserId || null }));
      this.message = text(this.pickedUserId ? 'Connector_User_Saved' : 'Connector_User_Cleared');
      this.dispatchEvent(new CustomEvent('changed'));
    });
  }

  async work(call) {
    this.message = undefined;
    this.error = undefined;
    this.working = true;
    try {
      await call();
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (failure && failure.body && failure.body.message) || text('Connector_Error_Unexpected');
  }
}
