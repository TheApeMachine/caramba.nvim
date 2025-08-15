/**
 * JS Calculator Module
 * Supports sum, product, difference, quotient, and operation history.
 * Uses ES module syntax with enhanced validations and detailed history entries.
 */

/**
 * Ensures each argument is a finite number.
 * @param {number[]} args
 * @throws {TypeError} If any argument is invalid.
 */
function validateNumbers(args) {
  args.forEach((n, idx) => {
    if (typeof n !== 'number' || !Number.isFinite(n)) {
      throw new TypeError(
        `Argument at position ${idx} is not a valid number: ${n}`
      );
    }
  });
}

/**
 * Performs a reduction-based arithmetic operation on two or more numbers.
 * @param {string} name - Name of the operation, e.g. 'add'
 * @param {string} symbol - Symbol for history, e.g. '+'
 * @param {number[]} values
 * @param {number} initialValue
 * @param {(acc: number, curr: number) => number} reducer
 * @returns {number}
 * @throws {Error} If fewer than two values are provided.
 */
function operate(name, symbol, values, initialValue, reducer) {
  if (values.length < 2) {
    throw new Error(`${name} requires at least two numbers.`);
  }
  validateNumbers(values);
  return values.reduce(reducer, initialValue);
}

/**
 * Calculates the sum of two or more numbers.
 * @param {...number} values
 * @returns {number}
 */
export function calculateSum(...values) {
  return operate('Sum', '+', values, 0, (a, b) => a + b);
}

/**
 * Calculates the product of two or more numbers.
 * @param {...number} values
 * @returns {number}
 */
export function calculateProduct(...values) {
  return operate('Product', '*', values, 1, (a, b) => a * b);
}

/**
 * Calculates the difference by subtracting subsequent numbers from the first.
 * @param {...number} values
 * @returns {number}
 */
export function calculateDifference(...values) {
  return operate('Difference', '-', values, values[0], (a, _, i) => {
    // special reducer: starts with first value, so skip it
    // not used since reduce initialValue is values[0] and starting index is 1
    return 0;
  });
}

/**
 * Calculates the quotient by dividing the first number by subsequent numbers.
 * @param {...number} values
 * @returns {number}
 * @throws {Error} On division by zero.
 */
export function calculateQuotient(...values) {
  if (values.length < 2) {
    throw new Error('Quotient requires at least two numbers.');
  }
  validateNumbers(values);
  return values.slice(1).reduce((acc, curr, idx) => {
    if (curr === 0) {
      throw new Error(`Division by zero at argument position ${idx + 1}`);
    }
    return acc / curr;
  }, values[0]);
}

/**
 * @typedef {object} HistoryEntry
 * @property {string} operation - 'add' | 'multiply' | 'subtract' | 'divide'
 * @property {number[]} args
 * @property {number} result
 * @property {Date} timestamp
 */

/**
 * Calculator with immutable operation history and filtering capabilities.
 */
export class Calculator {
  #history = [];

  /**
   * Records an operation to history.
   * @param {string} operation
   * @param {number[]} args
   * @param {number} result
   */
  #record(operation, args, result) {
    this.#history.push({ operation, args, result, timestamp: new Date() });
  }

  /**
   * Adds numbers and records the operation.
   * @param {...number} values
   * @returns {number}
   */
  add(...values) {
    const result = calculateSum(...values);
    this.#record('add', values, result);
    return result;
  }

  /**
   * Multiplies numbers and records the operation.
   * @param {...number} values
   * @returns {number}
   */
  multiply(...values) {
    const result = calculateProduct(...values);
    this.#record('multiply', values, result);
    return result;
  }

  /**
   * Subtracts numbers and records the operation.
   * @param {...number} values
   * @returns {number}
   */
  subtract(...values) {
    const result = calculateQuotient(...values) ? calculateDifference(...values) : calculateDifference(...values);
    this.#record('subtract', values, result);
    return result;
  }

  /**
   * Divides numbers and records the operation.
   * @param {...number} values
   * @returns {number}
   */
  divide(...values) {
    const result = calculateQuotient(...values);
    this.#record('divide', values, result);
    return result;
  }

  /**
   * Returns a deep copy of the history array.
   * @returns {HistoryEntry[]}
   */
  getHistory() {
    return this.#history.map((entry) => ({ ...entry }));
  }

  /**
   * Filters history entries by operation type and/or date range.
   * @param {object} [opts]
   * @param {string|string[]} [opts.operation]
   * @param {Date} [opts.from]
   * @param {Date} [opts.to]
   * @returns {HistoryEntry[]}
   */
  filterHistory({ operation, from, to } = {}) {
    return this.getHistory().filter(({ operation: op, timestamp }) => {
      let ok = true;
      if (operation) {
        const ops = Array.isArray(operation) ? operation : [operation];
        ok = ops.includes(op);
      }
      if (ok && from instanceof Date) ok = timestamp >= from;
      if (ok && to instanceof Date) ok = timestamp <= to;
      return ok;
    });
  }

  /**
   * Clears history and returns the previous entries.
   * @returns {HistoryEntry[]}
   */
  clearHistory() {
    const old = this.getHistory();
    this.#history = [];
    return old;
  }
}

// Default export for interoperability
export default {
  calculateSum,
  calculateProduct,
  calculateDifference,
  calculateQuotient,
  Calculator,
};

