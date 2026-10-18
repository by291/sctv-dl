export class HttpInputError extends Error {
  readonly status: 400 | 404 | 405 | 504
  readonly allow: string | undefined

  constructor(message: string, status: 400 | 404 | 405 | 504 = 400, allow?: string) {
    super(message)
    this.status = status
    this.allow = allow
  }
}
