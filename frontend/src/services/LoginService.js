// @ts-check

// import HttpService from './HttpService';
import TokenService from './TokenService';
// import Config from '../config/config';

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
    // TODO wieder auf Backend-Aufruf umstellen, wenn dies implementiert ist.
    // await HttpService.get(`${Config.backendUrl}/api/login_check`);
    return true;
  }
  return false;
};

const login = async (credentials) => {
  // const resp = await HttpService.post(`${Config.backendUrl}/api/login`, credentials);
  if (credentials.userName === 'admin' && credentials.password === 'admin') {
    const resp = { data: { token: '1.2.3' } };
    const { token } = resp.data;
    storeToken(token);
    initializeTokenService(token);
  } else {
    throw new Error('Username or Password invalid');
  }
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
