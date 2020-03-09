const { protocol, host } = window.location;

const backendUrl = process.env.VUE_APP_BACKEND_URL || `${protocol}//${host}`;

export default {
  backendUrl,
};
