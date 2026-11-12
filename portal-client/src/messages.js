/**
 * The words the portal shows. English only; a site can pass its own copy of this object to
 * mountPortal to change any of them.
 */
export const MESSAGES = {
  emailHeading: 'Sign In',
  emailIntro: 'Enter your email address and we will send you a sign-in code.',
  emailLabel: 'Email',
  sendCode: 'Send Me a Code',
  codeHeading: 'Check Your Email',
  codeIntro:
    'If that email address can use this portal, a six-digit code is on its way. It works for a few minutes.',
  codeLabel: 'Code',
  signIn: 'Sign In',
  startAgain: 'Start Again',
  factorHeading: 'Authenticator Code',
  factorIntro: 'Enter the six-digit code from your authenticator app.',
  enrollHeading: 'Set Up Your Authenticator',
  enrollIntro:
    'This portal asks for a code from an authenticator app as well as the emailed code. Add this key to your app, then enter the code it shows.',
  enrollKey: 'Key',
  enrollLink: 'Open in an authenticator app',
  signOut: 'Sign Out',
  save: 'Save',
  add: 'Add',
  cancel: 'Cancel',
  edit: 'Edit',
  saved: 'Saved.',
  yes: 'Yes',
  no: 'No',
  nothingHere: 'Nothing to show here yet.',
  search: 'Search',
  loading: 'Loading...',
  greeting: 'Hello, {0}',
  errors: {
    code_invalid: 'That code did not work. Check it, or start again for a new one.',
    code_expired: 'That code has expired. Start again for a new one.',
    locked: 'Too many wrong codes. Try again later.',
    not_signed_in: 'Please sign in again.',
    not_allowed: 'That change is not allowed here.',
    not_found: 'That record is not available.',
    required_missing: 'Fill in every required field.',
    invalid_value: 'One of the values is not one this field takes.',
    save_failed: 'The change could not be saved.',
    action_failed: 'That did not work. Try again later.',
    portal_unavailable: 'This portal is not available right now.',
    network_error: 'The portal could not be reached. Check your connection.',
    default: 'Something went wrong. Try again later.'
  }
};

/** The message for a refusal code. */
export function errorText(messages, code) {
  return messages.errors[code] || messages.errors.default;
}
