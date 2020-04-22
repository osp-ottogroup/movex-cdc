// @ts-check

/**
 * A ServerError is used when a http request fails.
 */
class ServerError extends Error {
  /**
   * Creates a new ServerError
   * @param {String} message error message
   * @param {Array} errors an array with a list of error messages
   * @param {Number} httpStatus HTTP status code
   */
  constructor(message, errors, httpStatus) {
    // the call to the super constructor of Error will not put a given message to this.message
    // see https://stackoverflow.com/questions/31089801/extending-error-in-javascript-with-es6-syntax-babel
    // so this.message has to be set explicitly
    super();
    this.message = message;
    this.errors = errors;
    this.httpStatus = httpStatus;
    this.name = this.constructor.name;
    this.stack = (new Error()).stack;
  }
}

export default ServerError;
