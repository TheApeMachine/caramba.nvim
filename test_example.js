// test_example.js
'use strict';
/**
 * Lightweight JS Calculator with history support.
 * Provides sum, product, difference, and quotient operations.
 */

/**
 * Validates all inputs are finite numbers.
 * @param {number[]} nums
 * @throws {TypeError} If any element is not a finite number.
 */
function validateNumbers(nums) {
  for (const [i, n] of nums.entries()) {
    if (typeof n !== 'number' || !Number.isFinite(n)) {
      throw new TypeError(`Argument ${i} is not a finite number: ${n}`);
    }
  }
}

/**
 * Definition of supported operations.
 * - init: initial accumulator value (unless useFirstAsInit is true)
 * - fn: reduction function (accumulator, current, index)
 * - minArgs: minimum count of arguments
 * - errorName: display name in errors
 * - useFirstAsInit: take the first element as init value
 */
const OPERATIONS = Object.freeze({
  sum: Object.freeze({
    init: 0,
    fn: (a, b) => a + b,
    minArgs: 0,
    errorName: 'Sum',
  }),
  product: Object.freeze({
    init: 1,
    fn: (a, b) => a * b,
    minArgs: 0,
    errorName: 'Product',
  }),
  difference: Object.freeze({
    fn: (a, b) => a - b,
    minArgs: 2,
    errorName: 'Difference',
    useFirstAsInit: true,
  }),
  quotient: Object.freeze({
    fn: (a, b, idx) => {
      if (b === 0) {
        throw new Error(`Division by zero at position ${idx + 1}`);
      }
      return a / b;
    },
    minArgs: 2,
    errorName: 'Quotient',
    useFirstAsInit: true,
  }),
});

/**
 * Generic calculator function.
 * @param {'sum'|'product'|'difference'|'quotient'} operationName
 * @param {number[]} nums
 * @returns {number}
 */
function calculate(operationName, nums) {
  const op = OPERATIONS[operationName];
  if (!op) {
    throw new Error(`Unsupported operation: ${operationName}`);
  }
  if (nums.length < op.minArgs) {
    const plural = op.minArgs === 1 ? '' : 's';
    throw new Error(`${op.errorName} requires at least ${op.minArgs} argument${plural}.`);
  }
  validateNumbers(nums);
  let accumulator;
  let rest;
  if (op.useFirstAsInit) {
    [accumulator, ...rest] = nums;
  } else {
    accumulator = op.init;
    rest = nums;
  }
  return rest.reduce((acc, curr, idx) => op.fn(acc, curr, idx), accumulator);
}

/**
 * Adds numbers.
 * @param {...number} nums
 * @returns {number}
 */
export const calculateSum = (...nums) => calculate('sum', nums);

/**
 * Multiplies numbers.
 * @param {...number} nums
 * @returns {number}
 */
export const calculateProduct = (...nums) => calculate('product', nums);

/**
 * Subtracts numbers (left-associative).
 * @param {...number} nums
 * @returns {number}
 */
export const calculateDifference = (...nums) => calculate('difference', nums);

/**
 * Divides numbers (left-associative).
 * @param {...number} nums
 * @returns {number}
 */
export const calculateQuotient = (...nums) => calculate('quotient', nums);

/**
 * Represents a calculator that records operation history.
 */
export class Calculator {
  #history = [];

  /**
   * Records an operation into history.
   * @param {string} opName
   * @param {number[]} args
   * @param {number} result
   */
  #record(opName, args, result) {
    const entry = Object.freeze({
      operation: opName,
      args: [...args],
      result,
      timestamp: new Date(),
    });
    this.#history.push(entry);
  }

  /** @returns {number} */
  add(...nums) {
    const result = calculateSum(...nums);
    this.#record('sum', nums, result);
    return result;
  }

  /** @returns {number} */
  multiply(...nums) {
    const result = calculateProduct(...nums);
    this.#record('product', nums, result);
    return result;
  }

  /** @returns {number} */
  subtract(...nums) {
    const result = calculateDifference(...nums);
    this.#record('difference', nums, result);
    return result;
  }

  /** @returns {number} */
  divide(...nums) {
    const result = calculateQuotient(...nums);
    this.#record('quotient', nums, result);
    return result;
  }

  /**
   * Returns a shallow copy of the operation history.
   * @returns {Array<{operation:string, args:number[], result:number, timestamp:Date}>}
   */
  getHistory() {
    return [...this.#history];
  }

  /**
   * Filters history by operation type and/or timestamp range.
   * @param {{operation?: string|string[], from?: Date, to?: Date}} [filter]
   * @returns {Array<object>}
   */
  filterHistory({ operation, from, to } = {}) {
    const ops = operation
      ? Array.isArray(operation)
        ? operation
        : [operation]
      : null;
    return this.getHistory().filter(({ operation: opName, timestamp }) =>
      (!ops || ops.includes(opName)) &&
      (!from || timestamp >= from) &&
      (!to || timestamp <= to)
    );
  }

  /**
   * Clears the history and returns the previous entries.
   * @returns {Array<object>}
   */
  clearHistory() {
    const old = this.getHistory();
    this.#history = [];
    return old;
  }
}

export default { calculateSum, calculateProduct, calculateDifference, calculateQuotient, Calculator };
