import { getErrorMessageAsHtml } from '@/helpers';
import ServerError from '@/models/ServerError';

describe('helpers.js', () => {
  describe('getErrorMessageAsHtml()', () => {
    it('should get message from arbitrary Error', () => {
      const error = new Error('ERROR');
      const errorMessage = getErrorMessageAsHtml(error);
      expect(errorMessage).toEqual('<div class="mt-2">ERROR</div>');
    });

    it('should get message from arbitrary Error with prepended message', () => {
      const error = new Error('ERROR');
      const errorMessage = getErrorMessageAsHtml(error, 'PREPEND');
      expect(errorMessage).toEqual('<div class="mt-2"><b>PREPEND</b></div><div class="mt-2">ERROR</div>');
    });

    it('should get message from ServerError if errors list is empty', () => {
      const error = new ServerError('SERVER_ERROR', [], 500);
      const errorMessage = getErrorMessageAsHtml(error);
      expect(errorMessage).toEqual('<div class="mt-2">SERVER_ERROR</div>');
    });

    it('should get message from ServerError if errors list is empty with prepended message', () => {
      const error = new ServerError('SERVER_ERROR', [], 500);
      const errorMessage = getErrorMessageAsHtml(error, 'PREPEND');
      expect(errorMessage).toEqual('<div class="mt-2"><b>PREPEND</b></div><div class="mt-2">SERVER_ERROR</div>');
    });

    it('should get errors from ServerError if errors list is not empty', () => {
      const error = new ServerError('SERVER_ERROR', ['ERROR_1', 'ERROR_2'], 500);
      const errorMessage = getErrorMessageAsHtml(error);
      expect(errorMessage).toEqual('<div class="mt-2">ERROR_1</div><div class="mt-2">ERROR_2</div>');
    });

    it('should get errors from ServerError if errors list is not empty with prepended message', () => {
      const error = new ServerError('SERVER_ERROR', ['ERROR_1', 'ERROR_2'], 500);
      const errorMessage = getErrorMessageAsHtml(error, 'PREPEND');
      expect(errorMessage).toEqual('<div class="mt-2"><b>PREPEND</b></div><div class="mt-2">ERROR_1</div><div class="mt-2">ERROR_2</div>');
    });

    it('should get default message if Error has no message', () => {
      const error = new Error();
      const errorMessage = getErrorMessageAsHtml(error);
      expect(errorMessage).toEqual('<div class="mt-2">An unknown error occurred!</div>');
    });

    it('should get default message if Error has no message with prepended message', () => {
      const error = new Error();
      const errorMessage = getErrorMessageAsHtml(error, 'PREPEND');
      expect(errorMessage).toEqual('<div class="mt-2"><b>PREPEND</b></div><div class="mt-2">An unknown error occurred!</div>');
    });

    it('should escape html chars correctly', () => {
      const error = new Error('_&_<_>_"_\'_/_');
      const errorMessage = getErrorMessageAsHtml(error);
      expect(errorMessage).toEqual('<div class="mt-2">_&amp;_&lt;_&gt;_&quot;_&#x27;_&#x2F;_</div>');
    });
  });
});
