const express = require('express');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const app = express();
app.use(express.json({ limit: '1mb' }));

const PORT = process.env.PORT || 8080;

app.get('/', (_req, res) => {
  res.status(200).send('billing kill-switch is alive');
});

app.post('/kill', async (req, res) => {
  console.log('Kill request body:', JSON.stringify(req.body));

  const allowKill =
    String(process.env.ALLOW_KILL || '').toLowerCase() === 'true';

  if (!allowKill) {
    return res.status(403).send('Kill not allowed');
  }

  try {
    await db.doc('system/maintenance').set({
      enabled: true,
      reason: req.body?.reason || 'billing anomaly',
      source: 'billing-killswitch',
      updatedAt: FieldValue.serverTimestamp(),
    });

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('Failed to write maintenance flag:', err);
    return res.status(500).json({ ok: false, error: 'write_failed' });
  }
});

app.use((err, _req, res, _next) => {
  console.error('Unexpected error:', err);
  res.status(500).json({ ok: false, error: 'internal' });
});

app.listen(PORT, () => {
  console.log(`Kill-switch service listening on port ${PORT}`);
});
