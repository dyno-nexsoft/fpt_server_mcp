import axios, { AxiosInstance, AxiosError } from 'axios';
import * as dotenv from 'dotenv';

dotenv.config();

/**
 * Error shape returned by the fpt_server REST API on failure responses.
 * @see docs/rest-api.md#errors
 */
export interface FptApiError {
  code: string;
  message: string;
  details?: any;
}

/** Thrown for any non-2xx response so callers get the API's stable `code`. */
export class FptRequestError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
    this.name = 'FptRequestError';
  }
}

/**
 * Client for the fpt_server REST API (`docs/rest-api.md`).
 *
 * Unlike ZentaoClient there is no login step — auth is a static API key sent
 * as `X-API-Key` on every request. GET responses are cached only for the
 * `/actions` catalogue (rarely changes); job/status endpoints are always
 * fetched fresh since callers rely on them for near-real-time state.
 */
export class FptServerClient {
  private client: AxiosInstance;
  private baseUrl = process.env.FPT_SERVER_BASE_URL || '';
  private apiKey = process.env.FPT_SERVER_API_KEY || '';
  private getCache = new Map<string, { data: any; timestamp: number }>();
  /** Only endpoints in this set are cached; everything else always hits the network. */
  private cacheableTtlMs = new Map<string, number>([
    ['/actions', 5 * 60 * 1000],
  ]);

  constructor(customClient?: AxiosInstance) {
    this.client = customClient || axios.create({
      baseURL: this.baseUrl,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    this.client.interceptors.request.use((config) => {
      if (this.apiKey) {
        config.headers['X-API-Key'] = this.apiKey;
      }
      return config;
    });

    this.client.interceptors.response.use(
      (response) => response,
      (error: AxiosError<{ error?: FptApiError }>) => {
        const status = error.response?.status ?? 0;
        const apiError = error.response?.data?.error;
        return Promise.reject(new FptRequestError(
          status,
          apiError?.code || 'request_failed',
          apiError?.message || error.message
        ));
      }
    );
  }

  /** Clears the in-memory cache. Helpful for testing and after any mutation. */
  public clearCache(): void {
    this.getCache.clear();
  }

  /**
   * Performs a GET request, caching the response only for paths configured
   * in {@link cacheableTtlMs} (matched by prefix, ignoring query string).
   */
  public async get<T>(url: string): Promise<T> {
    const path = url.split('?')[0];
    const ttl = this.cacheableTtlMs.get(path);

    if (ttl) {
      const cached = this.getCache.get(url);
      if (cached && Date.now() - cached.timestamp < ttl) {
        return cached.data;
      }
    }

    const res = await this.client.get<T>(url);

    if (ttl) {
      this.getCache.set(url, { data: res.data, timestamp: Date.now() });
    }
    return res.data;
  }

  /** POST helper. Clears the cache since a mutation may invalidate cached catalogues. */
  public async post<T>(url: string, data?: any): Promise<T> {
    this.clearCache();
    const res = await this.client.post<T>(url, data);
    return res.data;
  }

  /**
   * GET that also returns response headers, uncached. Used for
   * `/jobs/{id}/log`, whose `X-Log-Next-Offset` header drives polling.
   */
  public async getWithHeaders<T>(url: string): Promise<{ data: T; headers: Record<string, string> }> {
    const res = await this.client.get<T>(url);
    return { data: res.data, headers: res.headers as unknown as Record<string, string> };
  }
}
