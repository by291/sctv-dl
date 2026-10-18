import { z } from 'zod'

import { HttpInputError } from './input-error.ts'

import { UpstreamError, UpstreamTimeoutError } from '../programmes/programme-client.ts'
import { ProgrammeUnavailableError } from './programme-service.ts'

import type { ApplicationError } from '../../shared/contracts/errors.ts'

interface ClientApiFailure {
  status: number
  error: ApplicationError
  allow?: string
}

export function describeClientApiError(cause: unknown, signal: AbortSignal): ClientApiFailure {
  if (
    signal.aborted ||
    cause instanceof UpstreamTimeoutError ||
    (cause instanceof HttpInputError && cause.status === 504)
  ) {
    return {
      status: 504,
      error: { code: 'timeout', message: '节目服务请求超时，请稍后重试' },
    }
  }

  if (cause instanceof HttpInputError) {
    return {
      status: cause.status,
      allow: cause.allow,
      error: {
        code: cause.status === 404 ? 'not-found' : 'invalid-input',
        message: cause.message,
      },
    }
  }

  if (cause instanceof ProgrammeUnavailableError) {
    return { status: 404, error: { code: cause.code, message: cause.message } }
  }

  if (cause instanceof z.ZodError) {
    return { status: 400, error: { code: 'invalid-input', message: '请求参数无效' } }
  }

  if (cause instanceof UpstreamError) {
    return { status: 502, error: { code: 'upstream', message: cause.message } }
  }

  return { status: 500, error: { code: 'upstream', message: '节目服务暂不可用' } }
}
