// @ts-check

import TokenService from './TokenService';
import FetchService from './FetchService';
import ServerError from '../models/ServerError';
// eslint-disable-next-line import/no-cycle
import LoginService from './LoginService';

const HTTP_STATUS_CODE_401 = 401; // Unauthorized

const DEFAULT_HEADER = {
  Accept: 'application/json',
  'Content-Type': 'application/json',
};

/**
 * Calls the internal fetch-method and checks the response for HTTP-Status-Code 401 (Unauthorized).
 * In case of HTTP-Status-Code 401 a new access token will be requested
 * and the last request will be retried.
 * @param {URL} url URL-Object with the URL to request
 * @param {Object} requestOptions An options object containing any custom settings
 *                                that you want to apply to the request (see fetch() documentation)
 * @returns {promise} see doc at FetchService.doFetch()
 */
const doFetch = async (url, requestOptions) => {
  try {
    return FetchService.fetch(url, requestOptions);
  } catch (e) {
    if (e instanceof ServerError && e.httpStatus === HTTP_STATUS_CODE_401) {
      LoginService.logout(); // page reload
    }
    throw e;
  }
};

/**
 * Merges DEFAULT_HEADER and custom header options.
 * Custom header options override DEFAULT_HEADER-options
 * @param {Object} headerOptions custom header options
 * @returns {Object} merged header options
 */
const mergeHeaderOptions = headerOptions => Object.assign(
  {},
  DEFAULT_HEADER,
  { Authorization: `Bearer ${TokenService.getAccessToken()}` },
  headerOptions,
);

/**
 * Creates request options
 * @param {String} method HTTP method
 * @param {Object} headerOptions custom header options
 * @param {any} requestData data for the request body; will not be modified
 * @returns {Object} object with request options
 */
const createRequestOptions = (method, headerOptions, requestData) => {
  const requestOptions = {
    method,
    headers: mergeHeaderOptions(headerOptions),
  };
  if (requestData) {
    requestOptions.body = requestData;
  }

  return requestOptions;
};

/**
 * Makes a HTTP request with method GET
 * @param {String} urlString URL to request
 * @param {Object} urlParams Object with key/value-pairs for URL parameters
 * @param {Object} headerOptions custom header options
 * @returns {promise} see doc at FetchService.doFetch()
 */
const get = (urlString, urlParams = {}, headerOptions = {}) => {
  const url = new URL(urlString);
  url.search = (new URLSearchParams(urlParams)).toString();

  return doFetch(url, createRequestOptions('GET', headerOptions, null));
};

/**
 * Makes a HTTP request with method POST
 * @param {String} urlString URL to request
 * @param {Object} data data to use in request body (will be stringified as JSON)
 * @param {Object} headerOptions custom header options
 * @returns {promise} see doc at FetchService.doFetch()
 */
const post = (urlString, data = {}, headerOptions = {}) => {
  const url = new URL(urlString);
  const json = JSON.stringify(data);

  return doFetch(url, createRequestOptions('POST', headerOptions, json));
};

/**
 * Makes a HTTP request with method PUT
 * @param {String} urlString URL to request
 * @param {Object} data data to use in request body (will be stringified as JSON)
 * @param {Object} headerOptions custom header options
 * @returns {promise} see doc at FetchService.doFetch()
 */
const put = (urlString, data = {}, headerOptions = {}) => {
  const url = new URL(urlString);
  const json = JSON.stringify(data);

  return doFetch(url, createRequestOptions('PUT', headerOptions, json));
};

/**
 * Makes a HTTP request with method DELETE
 * @param {String} urlString URL to request
 * @param {Object} headerOptions custom header options
 * @returns {promise} see doc at FetchService.doFetch()
 */
const callDelete = (urlString, data, headerOptions = {}) => {
  const url = new URL(urlString);
  const json = JSON.stringify(data);

  return doFetch(url, createRequestOptions('DELETE', headerOptions, json));
};

export default {
  get,
  post,
  put,
  delete: callDelete,
};
