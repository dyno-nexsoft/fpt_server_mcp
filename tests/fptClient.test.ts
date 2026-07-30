import { jest } from '@jest/globals';
import { FptServerClient, FptRequestError } from '../src/fptClient.js';

function makeMockAxios(handlers: { get?: jest.Mock; post?: jest.Mock }) {
  const requestInterceptors: any[] = [];
  const responseInterceptors: any[] = [];
  return {
    get: handlers.get ?? jest.fn(),
    post: handlers.post ?? jest.fn(),
    interceptors: {
      request: { use: (fn: any) => requestInterceptors.push(fn) },
      response: { use: (onFulfilled: any, onRejected: any) => responseInterceptors.push({ onFulfilled, onRejected }) },
    },
    _requestInterceptors: requestInterceptors,
    _responseInterceptors: responseInterceptors,
  } as any;
}

describe('FptServerClient', () => {
  test('caches /actions GET responses but not other paths', async () => {
    const get = jest.fn()
      .mockResolvedValueOnce({ data: { actions: ['a'] }, headers: {} })
      .mockResolvedValueOnce({ data: { jobs: [] }, headers: {} })
      .mockResolvedValueOnce({ data: { jobs: [] }, headers: {} });
    const client = new FptServerClient(makeMockAxios({ get }));

    await client.get('/actions');
    await client.get('/actions'); // should hit cache, not call axios again
    await client.get('/jobs');
    await client.get('/jobs'); // uncached path, should call axios again

    expect(get).toHaveBeenCalledTimes(3);
  });

  test('post clears the cache so a subsequent GET refetches', async () => {
    const get = jest.fn()
      .mockResolvedValueOnce({ data: { actions: ['a'] }, headers: {} })
      .mockResolvedValueOnce({ data: { actions: ['b'] }, headers: {} });
    const post = jest.fn().mockResolvedValueOnce({ data: { ok: true }, headers: {} });
    const client = new FptServerClient(makeMockAxios({ get, post }));

    await client.get('/actions');
    await client.post('/jobs/x/cancel');
    const second = await client.get<any>('/actions');

    expect(get).toHaveBeenCalledTimes(2);
    expect(second.actions).toEqual(['b']);
  });

  test('wraps an error response into FptRequestError with the API code/message', async () => {
    const axiosMock = makeMockAxios({});
    new FptServerClient(axiosMock);
    const [{ onRejected }] = axiosMock._responseInterceptors;

    const apiError = {
      response: {
        status: 409,
        data: { error: { code: 'job.already_finished', message: 'Build đã kết thúc' } },
      },
      message: 'Request failed with status code 409',
    };

    await expect(onRejected(apiError)).rejects.toMatchObject({
      status: 409,
      code: 'job.already_finished',
      message: 'Build đã kết thúc',
    });
    await expect(onRejected(apiError)).rejects.toBeInstanceOf(FptRequestError);
  });
});
