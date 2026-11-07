/**
 * The portal in the browser: the sign-in screens (email, emailed code, authenticator) and the
 * template's pages (the person's own record, their related records, a catalog), with edit forms
 * for the fields the template allows. Framework-free; text is only ever set with textContent, so
 * nothing from a record is read as HTML.
 */
import { MESSAGES, errorText } from './messages.js';

const INPUT_TYPES = {
  email: 'email',
  phone: 'tel',
  url: 'url',
  date: 'date',
  datetime: 'datetime-local',
  double: 'number',
  integer: 'number',
  currency: 'number',
  percent: 'number'
};

function el(tag, attrs, children) {
  const node = document.createElement(tag);
  Object.entries(attrs || {}).forEach(([name, value]) => {
    if (name === 'text') {
      node.textContent = value;
    } else if (name === 'onClick') {
      node.addEventListener('click', value);
    } else if (name === 'onSubmit') {
      node.addEventListener('submit', (event) => {
        event.preventDefault();
        value(event);
      });
    } else if (value !== undefined && value !== null && value !== false) {
      node.setAttribute(name, value === true ? '' : value);
    }
  });
  (children || []).forEach((child) => child && node.appendChild(child));
  return node;
}

function fill(template, value) {
  return template.replace('{0}', value);
}

function display(field, value) {
  if (value === null || value === undefined || value === '') {
    return '';
  }
  if (field.type === 'boolean') {
    return value ? 'Yes' : 'No';
  }
  const option = (field.options || []).find((o) => o.value === value);
  return option ? option.label : String(value);
}

function inputFor(field, value, id) {
  const common = { id, name: field.field, required: field.required === true };
  if (field.options) {
    const select = el('select', common, [el('option', { value: '', text: '' })]);
    field.options.forEach((o) =>
      select.appendChild(
        el('option', { value: o.value, text: o.label, selected: o.value === value })
      )
    );
    return select;
  }
  if (field.type === 'boolean') {
    return el('input', { ...common, type: 'checkbox', checked: value === true, required: false });
  }
  if (field.type === 'textarea') {
    const area = el('textarea', common);
    area.value = value === null || value === undefined ? '' : String(value);
    return area;
  }
  const input = el('input', { ...common, type: INPUT_TYPES[field.type] || 'text' });
  input.value = value === null || value === undefined ? '' : String(value).replace(/Z$/, '');
  return input;
}

function valuesOf(form, fields) {
  const values = {};
  fields.forEach((field) => {
    const input = form.elements.namedItem(field.field);
    if (!input) {
      return;
    }
    values[field.field] =
      input.type === 'checkbox' ? input.checked : input.value === '' ? null : input.value;
  });
  return values;
}

/**
 * Shows the portal in `root`.
 * @param {HTMLElement} root the element to fill
 * @param {object} options
 * @param {object} options.api from createPortalApi
 * @param {object} [options.messages] replacement words (defaults to MESSAGES)
 * @returns {Promise<void>} once the first screen is shown
 */
export function mountPortal(root, { api, messages = MESSAGES }) {
  const state = { challenge: null, menu: null, pageKey: null };

  function show(...nodes) {
    root.replaceChildren(...nodes);
    const focusable = root.querySelector('input, select, textarea, button');
    if (focusable) {
      focusable.focus();
    }
  }

  function alertBox(text) {
    return el('p', { class: 'barn-portal-alert', role: 'alert', text });
  }

  function failed(error, alertSlot) {
    const code = error && error.code ? error.code : 'default';
    if (code === 'not_signed_in') {
      return emailScreen(errorText(messages, code));
    }
    alertSlot.replaceChildren(alertBox(errorText(messages, code)));
    return undefined;
  }

  function codeForm(heading, intro, extra, submit) {
    const alertSlot = el('div');
    const form = el(
      'form',
      { onSubmit: () => submit(form.elements.namedItem('code').value, alertSlot) },
      [
        el('label', { for: 'barn-portal-code', text: messages.codeLabel }),
        el('input', {
          id: 'barn-portal-code',
          name: 'code',
          inputmode: 'numeric',
          autocomplete: 'one-time-code',
          pattern: '[0-9]{6}',
          maxlength: '6',
          required: true
        }),
        el('button', { type: 'submit', text: messages.signIn })
      ]
    );
    show(
      el('h2', { text: heading }),
      el('p', { text: intro }),
      ...extra,
      alertSlot,
      form,
      el('button', {
        type: 'button',
        class: 'barn-portal-link',
        text: messages.startAgain,
        onClick: () => emailScreen()
      })
    );
  }

  function afterCode(result, alertSlot) {
    if (result.status === 'signedIn') {
      return home();
    }
    if (result.status === 'secondFactor') {
      return codeForm(messages.factorHeading, messages.factorIntro, [], secondFactor);
    }
    if (result.status === 'enroll') {
      return codeForm(
        messages.enrollHeading,
        messages.enrollIntro,
        [
          el('p', {}, [
            el('strong', { text: messages.enrollKey + ': ' }),
            el('code', { text: result.secret })
          ]),
          el('p', {}, [el('a', { href: result.uri, text: messages.enrollLink })])
        ],
        secondFactor
      );
    }
    return failed({ code: 'default' }, alertSlot);
  }

  function secondFactor(code, alertSlot) {
    return api
      .secondFactor(state.challenge, code)
      .then((result) => afterCode(result, alertSlot))
      .catch((error) => failed(error, alertSlot));
  }

  function emailScreen(notice) {
    const alertSlot = el('div', {}, [notice ? alertBox(notice) : null]);
    const form = el(
      'form',
      {
        onSubmit: () =>
          api
            .start(form.elements.namedItem('email').value.trim())
            .then((answer) => {
              state.challenge = answer.challenge;
              codeForm(messages.codeHeading, messages.codeIntro, [], (code, slot) =>
                api
                  .verify(state.challenge, code)
                  .then((result) => afterCode(result, slot))
                  .catch((error) => failed(error, slot))
              );
            })
            .catch((error) => failed(error, alertSlot))
      },
      [
        el('label', { for: 'barn-portal-email', text: messages.emailLabel }),
        el('input', {
          id: 'barn-portal-email',
          name: 'email',
          type: 'email',
          autocomplete: 'email',
          required: true
        }),
        el('button', { type: 'submit', text: messages.sendCode })
      ]
    );
    show(
      el('h2', { text: messages.emailHeading }),
      el('p', { text: messages.emailIntro }),
      alertSlot,
      form
    );
  }

  function recordForm(page, record, alertSlot, onDone) {
    const editable = page.fields.filter((f) => f.edit);
    const values = record ? record.values : {};
    const form = el('form', {
      class: 'barn-portal-form',
      onSubmit: () =>
        api
          .save(page.key, record ? record.id : null, valuesOf(form, editable))
          .then(() => openPage(page.key, messages.saved))
          .catch((error) => failed(error, alertSlot))
    });
    editable.forEach((field, i) => {
      const id = 'barn-portal-' + (record ? record.id : 'new') + '-' + i;
      form.appendChild(el('label', { for: id, text: field.label + (field.required ? ' *' : '') }));
      form.appendChild(inputFor(field, values[field.field], id));
    });
    form.appendChild(el('button', { type: 'submit', text: messages.save }));
    form.appendChild(el('button', { type: 'button', text: messages.cancel, onClick: onDone }));
    return form;
  }

  function recordCard(page, record, alertSlot) {
    const card = el('section', { class: 'barn-portal-record' });
    const list = el('dl');
    page.fields.forEach((field) => {
      list.appendChild(el('dt', { text: field.label }));
      list.appendChild(el('dd', { text: display(field, record.values[field.field]) }));
    });
    const buttons = el('div', { class: 'barn-portal-actions' });
    if (page.canUpdate && page.fields.some((f) => f.edit)) {
      buttons.appendChild(
        el('button', {
          type: 'button',
          text: messages.edit,
          onClick: () =>
            card.replaceChildren(recordForm(page, record, alertSlot, () => openPage(page.key)))
        })
      );
    }
    (page.actions || []).forEach((action) => {
      buttons.appendChild(
        el('button', {
          type: 'button',
          text: action.label,
          onClick: () =>
            api
              .action(page.key, record.id, action.name)
              .then((answer) =>
                alertSlot.replaceChildren(alertBox(answer.message || messages.saved))
              )
              .catch((error) => failed(error, alertSlot))
        })
      );
    });
    card.append(list, buttons);
    return card;
  }

  function nav() {
    const bar = el('nav', { class: 'barn-portal-nav' });
    state.menu.pages.forEach((page) => {
      bar.appendChild(
        el('button', {
          type: 'button',
          text: page.title || page.key,
          'aria-current': page.key === state.pageKey ? 'page' : null,
          onClick: () => openPage(page.key)
        })
      );
    });
    bar.appendChild(
      el('button', {
        type: 'button',
        text: messages.signOut,
        onClick: () => api.logout().finally(() => emailScreen())
      })
    );
    return bar;
  }

  function openPage(key, notice) {
    state.pageKey = key;
    const alertSlot = el('div', {}, [notice ? el('p', { role: 'status', text: notice }) : null]);
    return api
      .page(key)
      .then((page) => {
        const body = el('div');
        if (page.records.length === 0) {
          body.appendChild(el('p', { text: messages.nothingHere }));
        }
        page.records.forEach((record) => body.appendChild(recordCard(page, record, alertSlot)));
        if (page.canCreate) {
          body.appendChild(
            el('button', {
              type: 'button',
              text: messages.add,
              onClick: () =>
                body.replaceChildren(recordForm(page, null, alertSlot, () => openPage(key)))
            })
          );
        }
        show(
          el('h2', { text: state.menu.title }),
          el('p', { text: fill(messages.greeting, state.menu.firstName || '') }),
          nav(),
          el('h3', { text: page.title || page.key }),
          alertSlot,
          body
        );
      })
      .catch((error) => failed(error, alertSlot));
  }

  function home() {
    show(el('p', { role: 'status', text: messages.loading }));
    return api
      .me()
      .then((menu) => {
        state.menu = menu;
        return openPage(menu.pages[0].key);
      })
      .catch((error) => {
        if (error && error.code === 'not_signed_in') {
          return emailScreen();
        }
        const slot = el('div');
        show(slot);
        return failed(error, slot);
      });
  }

  return home();
}
