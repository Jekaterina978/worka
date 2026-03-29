const { isMaintenanceError } = require('./is-maintenance-error');

function withHttpMaintenance(handler) {
  return async (req, res) => {
    try {
      return await handler(req, res);
    } catch (err) {
      if (isMaintenanceError(err)) {
        console.warn('Maintenance mode blocking write (http wrapper)');
        return res.status(503).json({ error: 'maintenance_mode' });
      }
      console.error(err);
      return res.status(500).json({ error: 'internal' });
    }
  };
}

module.exports = { withHttpMaintenance };
