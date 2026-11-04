import { PARTS, insertPart, positionAtOffset } from '../patternParts';

describe('patternParts', () => {
  it('lists the naming tokens and the two words the shipped patterns use', () => {
    expect(PARTS).toEqual(['{FirstName}', '{LastName}', '{Salutation}', 'and', 'Family']);
  });

  it('puts a part at the cursor with a space on each side only where needed', () => {
    expect(insertPart('The {LastName}', 'Family', 14, 14)).toEqual({
      value: 'The {LastName} Family',
      caret: 21
    });
    expect(insertPart('{LastName} Household', '{FirstName}', 0, 0)).toEqual({
      value: '{FirstName} {LastName} Household',
      caret: 11
    });
    expect(insertPart('The  Family', '{LastName}', 4, 4).value).toBe('The {LastName} Family');
  });

  it('replaces selected text, and adds at the end when there is no cursor', () => {
    expect(insertPart('Dear X', '{FirstName}', 5, 6).value).toBe('Dear {FirstName}');
    expect(insertPart('Dear', '{FirstName}').value).toBe('Dear {FirstName}');
    expect(insertPart('', 'and', 3, 3)).toEqual({ value: 'and', caret: 3 });
  });

  it('finds the nearest gap between characters for a drop offset', () => {
    const measure = (text) => text.length * 10;
    expect(positionAtOffset('abcd', 14, measure)).toBe(1);
    expect(positionAtOffset('abcd', 16, measure)).toBe(2);
    expect(positionAtOffset('abcd', 500, measure)).toBe(4);
    expect(positionAtOffset('abcd', 0, measure)).toBe(0);
    expect(positionAtOffset('abcd', 12)).toBe(4);
  });
});
