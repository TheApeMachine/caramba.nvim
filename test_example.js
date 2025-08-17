/**
 * Lightweight JS Calculator with history.
 */

const validate = nums => {
  nums.forEach((n,i) => {
    if (typeof n !== 'number' || !isFinite(n)) {
      throw new TypeError(`Arg ${i} not a number: ${n}`);
    }
  });
};

const operate = (nums, init, fn, name) => {
  if (nums.length < 2) throw new Error(`${name} requires at least two numbers.`);
  validate(nums);
  return nums.reduce(fn, init);
};

export const calculateSum = (...nums) => operate(nums, 0, (a,b) => a + b, 'Sum');
export const calculateProduct = (...nums) => operate(nums, 1, (a,b) => a * b, 'Product');
export const calculateDifference = (...nums) => {
  if (nums.length < 2) throw new Error('Difference requires at least two numbers.');
  validate(nums);
  const [first, ...rest] = nums;
  return rest.reduce((a,b) => a - b, first);
};
export const calculateQuotient = (...nums) => {
  if (nums.length < 2) throw new Error('Quotient requires at least two numbers.');
  validate(nums);
  const [first, ...rest] = nums;
  return rest.reduce((a,b,i) => {
    if (b === 0) throw new Error(`Division by zero at position ${i+1}`);
    return a / b;
  }, first);
};

export class Calculator {
  #history = [];
  #record(op, args, res) {
    this.#history.push({ operation: op, args, result: res, timestamp: new Date() });
  }
  add(...n) { const r = calculateSum(...n); this.#record('add', n, r); return r; }
  multiply(...n) { const r = calculateProduct(...n); this.#record('multiply', n, r); return r; }
  subtract(...n) { const r = calculateDifference(...n); this.#record('subtract', n, r); return r; }
  divide(...n) { const r = calculateQuotient(...n); this.#record('divide', n, r); return r; }
  getHistory() { return [...this.#history]; }
  filterHistory({ operation, from, to } = {}) {
    const ops = operation ? ([]).concat(operation) : null;
    return this.getHistory().filter(({ operation: op, timestamp: ts }) =>
      (!ops || ops.includes(op)) && (!from || ts >= from) && (!to || ts <= to)
    );
  }
  clearHistory() { const old = this.getHistory(); this.#history = []; return old; }
}

export default { calculateSum, calculateProduct, calculateDifference, calculateQuotient, Calculator };
