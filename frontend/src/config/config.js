const { protocol, host } = window.location;

// REPLACE_PUBLIC_PATH_BEFORE should be replaced in production with either an empty string if public root is /
// or with "/subpath" e.g. if locations are used in nginx etc.
const publicPath = import.meta.env.PROD ? '/REPLACE_PUBLIC_PATH_BEFORE' : '';

const backendUrl = import.meta.env.VITE_BACKEND_URL || `${protocol}//${host}${publicPath}`;

export default {
  backendUrl,
};
