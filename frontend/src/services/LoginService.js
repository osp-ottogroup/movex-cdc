// @ts-check

// eslint-disable-next-line import/no-cycle
import HttpService from './HttpService';
import TokenService from './TokenService';
import Config from '../config/config';

const TOKEN_KEY = 'login_token';

const loadToken = () => localStorage.getItem(TOKEN_KEY);
const storeToken = token => localStorage.setItem(TOKEN_KEY, token);
const removeToken = () => localStorage.removeItem(TOKEN_KEY);

const initializeTokenService = (token) => {
  TokenService.setAccessToken(token);
};

const checkStoredLogin = () => {
  const token = loadToken();
  if (token !== null) {
    initializeTokenService(token);
    return true;
  }
  return false;
};

const checkLogin = async () => {
  const isStoredLoginPresent = checkStoredLogin();
  if (isStoredLoginPresent) {
    // TODO login-check im backend?
    return true;
  }
  return false;
};

const login = async (credentials) => {
  const resp = await HttpService.post(`${Config.backendUrl}/login/do_logon`, credentials);
  const { token } = resp.data;
  storeToken(token);
  initializeTokenService(token);
};

const logout = () => {
  TokenService.setAccessToken(null);
  removeToken();
  window.location.reload();
};

export default {
  login,
  logout,
  checkLogin,
};
