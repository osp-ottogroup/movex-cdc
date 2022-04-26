const { protocol, host } = window.location;

// REPLACE_PUBLIC_PATH_BEFORE should be replaced in production with either an empty string if public root is /
// or with "/subpath" e.g. if locations are used in nginx etc.
const publicPath = process.env.NODE_ENV === 'production' ? '/REPLACE_PUBLIC_PATH_BEFORE' : '';

const backendUrl = process.env.VUE_APP_BACKEND_URL || `${protocol}//${host}${publicPath}`;

export default {
  backendUrl,
};
