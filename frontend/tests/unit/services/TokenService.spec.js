import TokenService from '@/services/TokenService';

describe('TokenService', () => {
  let token;
  let payload;

  beforeEach(() => {
    // header of test token
    // header = {
    //   alg: 'HS256',
    //   typ: 'JWT'
    // };
    // secret key for signature: 'my-secret-key'

    // Payload
    payload = {
      name: 'John Doe',
      exp: 1850911953, // Sat Aug 26 2028 16:12:33 GMT+0200 (Mitteleuropäische Sommerzeit)
    };

    token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiSm9obiBEb2UiLCJleHAiOjE4NTA5MTE5NTN9.Z4VphwK7DBe6pTEcOOPp2qBmCB1y7bj7_lkXkIDhXyA';
  });

  it('should set and get the token', () => {
    TokenService.setAccessToken(token);
    expect(TokenService.getAccessToken()).toEqual(token);
  });

  it.each([
    ['123.456'],
    ['123.456.'],
    ['.123.456'],
    ['.123.'],
    ['..'],
    ['.123.456.'],
    ['0.123.456.789'],
    [null],
  ])('should throw exception with ill-formed token: %s', (testToken) => {
    TokenService.setAccessToken(testToken);
    expect(() => TokenService.getPayload(testToken)).toThrow(TypeError);
  });

  it('should get the payload', () => {
    TokenService.setAccessToken(token);
    const actual = TokenService.getPayload();
    expect(actual).toEqual(payload);
  });
});
