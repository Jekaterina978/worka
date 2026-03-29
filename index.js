import express from 'express';
import { ServicesClient } from '@google-cloud/run';

const app = express();
app.use(express.json());

const REGION = 'europe-west3';
const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT || 'worka-416c0';
const DRY_RUN = String(process.env.DRY_RUN || 'true') === 'true';

const ALLOWLIST = ['oncvwrittensyncprivatecontacts'];

const client = new ServicesClient();

function parseMessage(req) {
  try {
    const data = req.body?.message?.data;
    if (!data) return null;
    return Buffer.from(data, 'base64').toString('utf8');
  } catch (e) {
    console.error('Parse error', e);
    return null;
  }
}

async function disableService(service) {
  const name = 'projects/' + PROJECT_ID + '/locations/' + REGION + '/services/' + service;

  console.log('Disabling ' + service);

  const [svc] = await client.getService({ name });

  svc.scaling = { manualInstanceCount: 0 };

  await client.updateService({ service: svc });

  console.log('Disabled ' + service);
}

app.post('/', async (req, res) => {
  try {
    const msg = parseMessage(req);

    console.log('🔥 Billing event:', msg);
    console.log('DRY_RUN:', DRY_RUN);

    if (DRY_RUN) {
      console.log('[DRY RUN] No action taken');
      return res.status(200).send('ok');
    }

    for (const service of ALLOWLIST) {
      try {
        await disableService(service);
      } catch (e) {
        console.error(e);
      }
    }

    res.status(200).send('done');
  } catch (e) {
    console.error(e);
    res.status(200).send('safe');
  }
});

app.listen(8080, () => {
  console.log('Kill switch running on port 8080');
});
