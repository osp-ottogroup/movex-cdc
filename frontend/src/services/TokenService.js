// @ts-check

let accessToken = null;

/**
 * decodes a base64 string
 * @param {string} base64String - string to decode
 * @returns {string} decoded string
 */
const decode = (base64String) => atob(base64String);

/**
 * splits the JWT in its three parts header, payload, and signature
 * @returns {object} A map with the keys 'header', 'payload', 'signature'
 *                   and the corresponding token values
 */
const getTokenParts = () => {
  if (!accessToken || accessToken === '') {
    throw new TypeError("The given JWT is empty. Expected the form of 'header.payload.signature'.");
  }

  const parts = accessToken.split('.');
  if (parts.length !== 3
      || parts[0] === ''
      || parts[1] === ''
      || parts[2] === ''
  ) {
    throw new TypeError(`The given JWT-Token is ill-formed. Expected the form of 'header.payload.signature'. Token=${accessToken}`);
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
  const parts = getTokenParts();
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
