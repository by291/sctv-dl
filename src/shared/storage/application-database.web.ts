export interface ApplicationDatabase {
  open(): Promise<IDBDatabase>
  dispose(): void
}

export function createApplicationDatabase(): ApplicationDatabase {
  let connection: IDBDatabase | undefined
  let opening: Promise<IDBDatabase> | undefined
  let disposed = false

  return {
    open() {
      if (disposed) {
        return Promise.reject(new Error('Application database disposed'))
      }

      if (opening) {
        return opening
      }

      const attempt = new Promise<IDBDatabase>((resolve, reject) => {
        if (!globalThis.indexedDB) {
          reject(new Error('IndexedDB unavailable'))

          return
        }

        const request = indexedDB.open('sctv-dl-app', 1)
        let rejected = false
        const fail = (error: unknown) => {
          rejected = true
          reject(error)
        }

        request.onupgradeneeded = () => {
          for (const name of [
            'history',
            'historySessions',
            'meta',
            'programmeCache',
            'browseState',
          ]) {
            if (!request.result.objectStoreNames.contains(name)) {
              request.result.createObjectStore(name)
            }
          }
        }

        request.onerror = () => fail(request.error)
        request.onblocked = () => fail(new Error('Application database upgrade blocked'))
        request.onsuccess = () => {
          if (disposed || rejected) {
            request.result.close()
            fail(new Error('Application database closed'))

            return
          }

          connection = request.result
          connection.onversionchange = () => {
            connection?.close()
            connection = undefined
            opening = undefined
          }

          resolve(connection)
        }
      })
      opening = attempt
      void attempt.catch(() => {
        // Failed opens are retryable; an older blocked request must not clear
        // a newer connection attempt when its delayed callback finally arrives.
        if (opening === attempt) {
          opening = undefined
        }
      })

      return attempt
    },
    dispose() {
      disposed = true
      connection?.close()
      connection = undefined
    },
  }
}
