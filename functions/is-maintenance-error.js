function isMaintenanceError(err) {
  if (!err) return false;
  return err.code === 'maintenance_mode' || err.message === 'maintenance_mode';
}

module.exports = { isMaintenanceError };
