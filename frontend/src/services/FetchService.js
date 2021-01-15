// @ts-check

import ServerError from '../models/ServerError';

/**
 * Extracts the data from the response object
 * @param {Response} response response returned by fetch
 * @returns {Promise<Object>} data from response
 */
const getResponseData = async (response) => {
  let data;
  const contentType = response.headers.get('content-type');
  if (contentType && contentType.indexOf('application/json') !== -1) {
    data = await response.json();
  } else {
    data = { text: await response.text() };
  }
  return data;
};

/**
 * Wraps the fetch() function and handles errors
 * @param {URL} url URL-Object with the URL to request
 * @param {Object} requestOptions An options object containing any custom settings
 *                                that you want to apply to the request (see fetch() documentation)
 * @returns {Promise} A Promise which resolves with an Object or rejects with a ServerError.
 *
 * @example It resolves for all HTTP status codes between 200 and 299 with an Object like:
 * {
 *   data: <the data of the response body; JSON for content-type 'application/json', otherwise text>
 *   status: <HTTP status code>
 * }
 * @example It rejects for all HTTP status codes not between 200 and 299 with a ServerError.
 * The ServerError has the following members:
 *   data:       the data of the response body;
 *               JSON for content-type 'application/json', otherwise text
 *   message:    error message
 *   httpStatus: HTTP status code
 *
 * In case of network errors the error itself will be rejected from the Promise.
 */
const doFetch = async (url, requestOptions) => {
  const response = await fetch(url, requestOptions);
  const data = await getResponseData(response);
  const httpStatus = response.status;
  if (!response.ok) { // HTTP-Status-Code != 200-299
    const errorMessage = `The request to ${url.toString()} responded with http-status-code ${response.status}: ${response.statusText}`;
    let errors = [];
    if (data.error) {
      errors.push(data.error);
    }
    if (data.exception) {
      errors.push(data.exception);
    }
    if (data.traces && data.traces instanceof Array) {
      data.traces['Application Trace'].forEach((t) => errors.push(t.trace));
    }
    if (data.errors && data.errors instanceof Array) {
      errors = [...errors, ...data.errors];
    }
    throw new ServerError(errorMessage, errors, httpStatus);
  }

  return {
    data,
    status: httpStatus,
  };
};

export default {
  fetch: doFetch,
};
