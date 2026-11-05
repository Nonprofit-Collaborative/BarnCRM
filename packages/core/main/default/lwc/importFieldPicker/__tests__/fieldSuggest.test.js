import { score, suggestFields, words } from '../fieldSuggest';

const OPTIONS = [
  { label: 'Do not load', value: 'Ignore' },
  { label: 'Person: First Name', value: 'Contact1.FirstName' },
  { label: 'Person: Last Name', value: 'Contact1.LastName' },
  { label: 'Person: Email', value: 'Contact1.Email' },
  { label: 'Second person: Email', value: 'Contact2.Email' },
  { label: 'Organization: Name', value: 'Organization.Name' },
  { label: 'Create New Field', value: 'NewField' }
];

describe('suggested fields for unmatched columns', () => {
  it('splits headings and labels into lower-case words', () => {
    expect(words('firstName')).toEqual(['first', 'name']);
    expect(words('E-mail  Address')).toEqual(['e', 'mail', 'address']);
    expect(words('')).toEqual([]);
  });

  it('scores whole words above word starts and zero for no likeness', () => {
    expect(score('First Name', 'Person: First Name')).toBe(4);
    expect(score('Organisation', 'Organization: Name')).toBe(0);
    expect(score('Emails', 'Person: Email')).toBe(1);
    expect(score('Zip', 'Person: Email')).toBe(0);
  });

  it('offers the best fields per heading, each once, never a used or skipped one', () => {
    const suggestions = suggestFields(['Email', 'Last Name'], OPTIONS, ['Contact1.Email'], {
      skip: ['Ignore', 'NewField']
    });
    expect(suggestions.map((option) => option.value)).toEqual([
      'Contact2.Email',
      'Contact1.LastName',
      'Contact1.FirstName',
      'Organization.Name'
    ]);
  });

  it('suggests nothing for a heading that looks like no field, and caps the list', () => {
    expect(suggestFields(['Favorite color'], OPTIONS, [], { skip: ['Ignore'] })).toEqual([]);
    expect(suggestFields(['Name'], OPTIONS, [], { max: 2, skip: ['Ignore'] })).toHaveLength(2);
  });
});
