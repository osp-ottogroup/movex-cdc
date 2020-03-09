// @ts-check

let accessToken = null;

/**
 * decodes a base64 string
 * @param {string} base64String - string to decode
 * @returns {string} decoded string
 */
const decode = base64String => atob(base64String);

/**
 * splits the JWT in its three parts header, payload, and signature
 * @param {string} token - JWT in the form of 'header.payload.signature'
 * @returns {object} A map with the keys 'header', 'payload', 'signature'
 *                   and the corresponding token values
 */
const getTokenParts = (token) => {
  if (!token || token === '') {
    throw new TypeError("The given JWT-Token is empty. Expected the form of 'header.payload.signature'.");
  }

  const parts = token.split('.');
  if (parts.length !== 3
      || parts[0] === ''
      || parts[1] === ''
      || parts[2] === ''
  ) {
    throw new TypeError(`The given JWT-Token is ill-formed. Expected the form of 'header.payload.signature'. Token=${token}`);
  }

  return {
    header: parts[0],
    payload: parts[1],
    signature: parts[2],
  };
};

/**
 * Extracts the payload from the access token and parses it to a JSON object
 * @returns {object} JSON object extracted and parsed from JWT
 */
const getPayload = () => {
  const parts = getTokenParts(accessToken);
  return JSON.parse(decode(parts.payload));
};

/**
 * @returns {string} the access token
 */
const getAccessToken = () => accessToken;

/**
 * @param newAccessToken
 */
const setAccessToken = (newAccessToken) => { accessToken = newAccessToken; };

export default {
  getAccessToken,
  getPayload,
  setAccessToken,
};
