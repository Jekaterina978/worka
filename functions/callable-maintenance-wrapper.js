const functions = require('firebase-functions');
const { isMaintenanceError } = require('./is-maintenance-error');

function withCallableMaintenance(handler) {
  return async (data, context) => {
    try {
      return await handler(data, context);
    } catch (err) {
      if (isMaintenanceError(err)) {
        console.warn('Maintenance mode blocking write (callable wrapper)');
        throw new functions.https.HttpsError('unavailable', 'maintenance_mode');
      }
      throw err;
    }
  };
}

module.exports = { withCallableMaintenance };
