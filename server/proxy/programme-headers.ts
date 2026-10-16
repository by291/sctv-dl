import { randomUUID } from 'node:crypto'
import { z } from 'zod'

import type { IncomingMessage, ServerResponse } from 'node:http'

const deviceCookieName = 'sctv-dl-device-id'
const deviceIdSchema = z.uuidv4()

export function programmeHeaders(
  request: IncomingMessage,
  response: ServerResponse,
  cookiePath = '/api',
): Record<string, string> {
  const stored = request.headers.cookie
    ?.split(';')
    .map((part) => part.trim())
    .find((part) => part.startsWith(`${deviceCookieName}=`))
    ?.slice(deviceCookieName.length + 1)
  const parsed = deviceIdSchema.safeParse(stored)
  const deviceId = parsed.success ? parsed.data : randomUUID()

  if (!parsed.success) {
    // Keep one simulated installation per browser; this cookie never goes upstream.
    response.setHeader(
      'Set-Cookie',
      `${deviceCookieName}=${deviceId}; Path=${cookiePath}; Max-Age=31536000; HttpOnly; SameSite=Lax`,
    )
  }

  // A coherent Android guest profile mirrors the inspected 9.6.1.5 APK.
  return {
    Accept: 'application/json',
    'Accept-Encoding': 'gzip',
    'User-Agent': 'okhttp/4.12.0',
    userId: '',
    Authorization: '',
    deviceId,
    deviceBrand: 'google',
    deviceModel: 'Pixel 8',
    systemVersion: '14',
    deviceType: 'android',
    appVersion: '9.6.1.5',
    captchaId: '',
  }
}
