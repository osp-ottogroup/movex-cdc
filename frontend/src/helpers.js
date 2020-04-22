// @ts-check

import ServerError from '@/models/ServerError';

// eslint-disable-next-line import/prefer-default-export
export const getErrorMessageAsHtml = (error, prependMessage = '') => {
  let errorMessage;

  if (error instanceof ServerError && error.errors.length > 0) {
    errorMessage = `<div>${error.errors.join('</div><div>')}</div>`;
  } else if (error.message) {
    errorMessage = `<div>${error.message}</div>`;
  } else {
    errorMessage = '<div>An unknown error occured!</div>';
  }

  if (prependMessage !== '') {
    errorMessage = `<div>${prependMessage}</div>${errorMessage}`;
  }

  return errorMessage;
};
