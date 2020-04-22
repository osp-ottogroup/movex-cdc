import ServerError from '@/models/ServerError';

describe('ServerError', () => {
  it('should be instantiated', () => {
    expect(() => new ServerError('error', {}, 500)).not.toThrow();
  });

  it('should be instance of ServerError', () => {
    expect((new ServerError('error', {}, 500)) instanceof ServerError).toBeTruthy();
  });

  it('should have name \'ServerError\'', () => {
    expect((new ServerError('error', {}, 500)).name).toEqual('ServerError');
  });

  it('should have message from constructor', () => {
    const message = 'error message';
    expect((new ServerError(message, {}, 500)).message).toEqual(message);
  });

  it('should have message from constructor, if data has no message', () => {
    const message = 'error message';
    const data = { otherData: 'data error message' };
    expect((new ServerError(message, data, 500)).message).toEqual(message);
  });
});
