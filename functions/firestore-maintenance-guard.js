// Global Firestore write guard: blocks all writes when maintenance is enabled.
// Uses Application Default Credentials (already initialized in index.js).
const admin = require('firebase-admin');
const { isMaintenanceMode } = require('./maintenance');

function wrapAsync(fn) {
  return async function wrapped(...args) {
    if (await isMaintenanceMode()) {
      console.warn('Maintenance mode blocking write');
      const err = new Error('maintenance_mode');
      err.code = 'maintenance_mode';
      throw err;
    }
    return fn.apply(this, args);
  };
}

// Patch document-level writes
const docProto = admin.firestore.DocumentReference.prototype;
docProto.set = wrapAsync(docProto.set);
docProto.update = wrapAsync(docProto.update);
docProto.delete = wrapAsync(docProto.delete);

// Patch collection add (uses set internally, but patch for safety)
const colProto = admin.firestore.CollectionReference.prototype;
colProto.add = wrapAsync(colProto.add);

// Patch batch writes
const batchProto = admin.firestore.WriteBatch.prototype;
batchProto.set = wrapAsync(batchProto.set);
batchProto.update = wrapAsync(batchProto.update);
batchProto.delete = wrapAsync(batchProto.delete);
batchProto.commit = wrapAsync(batchProto.commit);

// Patch runTransaction (check once before running)
const firestoreProto = admin.firestore.Firestore.prototype;
const originalRunTx = firestoreProto.runTransaction;
firestoreProto.runTransaction = async function (updateFunction, options) {
  if (await isMaintenanceMode()) {
    console.warn('Maintenance mode blocking transaction');
    const err = new Error('maintenance_mode');
    err.code = 'maintenance_mode';
    throw err;
  }
  return originalRunTx.call(this, updateFunction, options);
};

module.exports = {};
