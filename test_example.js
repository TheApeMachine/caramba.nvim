// Improved JavaScript calculator module
// - Uses ES module syntax
// - Supports multi-argument operations
// - Validates inputs
// - Provides immutable history reads
// - Includes JSDoc for better documentation

/**
 * Validates that each argument is a finite number.
 * @param {Array<number>} args
 * @throws {TypeError} If any argument is not a finite number.
 */
function validateNumbers(args) {
  args.forEach((n, idx) => {
    if (typeof n !== 'number' || !Number.isFinite(n)) {
      throw new TypeError(`Argument at position ${idx} is not a valid number: ${n}`);
    }
  });
}

/**
 * Calculates the sum of two or more numbers.
 * @param {...number} values
 * @returns {number}
 */
export function calculateSum(...values) {
  if (values.length < 2) {
    throw new Error('calculateSum requires at least two numbers');
  }
  validateNumbers(values);
  return values.reduce((total, n) => total + n, 0);
}

/**
 * Calculates the product of two or more numbers.
 * @param {...number} values
 * @returns {number}
 */
export function calculateProduct(...values) {
  if (values.length < 2) {
    throw new Error('calculateProduct requires at least two numbers');
  }
  validateNumbers(values);
  return values.reduce((total, n) => total * n, 1);
}

/**
 * A simple calculator with operation history.
 */
export class Calculator {
  constructor() {
    this._history = [];
  }

  /**
   * Adds numbers and records the operation.
   * @param {...number} values
   * @returns {number}
   */
  add(...values) {
    const result = calculateSum(...values);
    this._history.push(`${values.join(' + ')} = ${result}`);
    return result;
  }

  /**
   * Multiplies numbers and records the operation.
   * @param {...number} values
   * @returns {number}
   */
  multiply(...values) {
    const result = calculateProduct(...values);
    this._history.push(`${values.join(' * ')} = ${result}`);
    return result;
  }

  /**
   * Retrieves a copy of the history of operations.
   * @returns {Array<string>}
   */
  getHistory() {
    return [...this._history];
  }

  /**
   * Clears the history and returns the previous history.
   * @returns {Array<string>} The history before clearing.
   */
  clearHistory() {
    const oldHistory = this.getHistory();
    this._history = [];
    return oldHistory;
  }
}

// Default export for CommonJS compatibility
export default { calculateSum, calculateProduct, Calculator };
