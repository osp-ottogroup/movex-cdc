const { protocol, host } = window.location;

// if <base href="http://host:port/path" is set in html head section then
// - the href from <base> is used as backend URL
// - all relative links are suffixed with host:port of the baseHref if the relative link starts with /
// - all relative links are suffixed with the whole baseHref if relate link doe not start with /
// used to fix location problems in nginx or apache by injecting a <base> tag in head section
const baseHref = (document.getElementsByTagName('base')[0] || {}).href;

const backendUrl = process.env.VUE_APP_BACKEND_URL || baseHref || `${protocol}//${host}`;

export default {
  backendUrl,
};
