import HttpService from '@/services/HttpService';
import LoginService from '@/services/LoginService';
import TokenService from '@/services/TokenService';
import Config from '@/config/config';

jest.mock('@/services/HttpService');

describe('LoginService', () => {
  it('should login', async () => {
    const credentials = {
      username: 'user',
      password: 'password',
    };
    const response = { data: { token: 'test-token' } };
    HttpService.post.mockResolvedValueOnce(response);

    await LoginService.login(credentials);

    expect(HttpService.post).toHaveBeenCalledWith(`${Config.backendUrl}/login/do_logon`, credentials);
    expect(HttpService.post).toHaveBeenCalledTimes(1);
    expect(TokenService.getAccessToken()).toEqual(response.data.token);
  });

  it('should logout', () => {
    const { location } = window;
    delete window.location;
    window.location = { reload: jest.fn() };

    LoginService.logout();

    expect(TokenService.getAccessToken()).toBeNull();
    expect(window.location.reload).toHaveBeenCalled()

    window.location = location;
  });

  it('should login if token exists', () => {
    const token = 'test-token';
    localStorage.setItem('login_token', token);

    expect(LoginService.loginWithExistingToken()).toBeTruthy();
    expect(TokenService.getAccessToken()).toEqual(token);
  });

  it('should not login if token does not exist', () => {
    localStorage.removeItem('login_token');
    TokenService.setAccessToken(null);
    expect(LoginService.loginWithExistingToken()).toBeFalsy();
    expect(TokenService.getAccessToken()).toBeNull();
  });
});
