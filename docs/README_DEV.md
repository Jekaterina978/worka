# Worka Dev Notes

## Firestore Composite Indexes

Used by responses lists:
- `where(type) + where(candidateOwnerId) + orderBy(createdAt desc)`
- `where(type) + where(employerOwnerId) + orderBy(createdAt desc)`
- `where(type) + where(candidateOwnerId) + orderBy(updatedAt desc)`
- `where(type) + where(employerOwnerId) + orderBy(updatedAt desc)`

1. `responses`: `type` ASC, `candidateOwnerId` ASC, `createdAt` DESC
2. `responses`: `type` ASC, `employerOwnerId` ASC, `createdAt` DESC
3. `responses`: `type` ASC, `candidateOwnerId` ASC, `updatedAt` DESC
4. `responses`: `type` ASC, `employerOwnerId` ASC, `updatedAt` DESC
5. `responses`: `type` ASC, `candidateOwnerId` ASC, `status` ASC, `createdAt` DESC
6. `responses`: `type` ASC, `employerOwnerId` ASC, `status` ASC, `createdAt` DESC

For test collection, same set for `responses_test`.

Deploy (always specify project):

```bash
firebase deploy --only firestore:indexes --project your-dev-alias
# prod only when intended:
# firebase deploy --only firestore:indexes --project prod
```
