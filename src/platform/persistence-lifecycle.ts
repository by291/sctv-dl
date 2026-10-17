export interface PersistenceOwner {
  getWriteRevision(): number
  flush(): Promise<void>
  isPersisted(): Promise<boolean>
}

export async function flushPersistence(owners: PersistenceOwner[]): Promise<boolean> {
  try {
    for (;;) {
      const revisions = owners.map((owner) => owner.getWriteRevision())
      await Promise.all(owners.map((owner) => owner.flush()))
      const persisted = await Promise.all(owners.map((owner) => owner.isPersisted()))
      if (persisted.some((saved) => !saved)) {
        return false
      }

      // A history callback can queue work while settings finishes (and vice versa).
      if (owners.every((owner, index) => owner.getWriteRevision() === revisions[index])) {
        return true
      }
    }
  } catch {
    return false
  }
}
