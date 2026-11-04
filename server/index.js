import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createApp } from './src/app.js';

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.PORT ?? 3000);
const app = createApp({ dataFile: join(here, 'data/state.json'), certsDir: join(here, 'certs') });

app.listen(port, '0.0.0.0', () => {
  console.log(`Consentra server on :${port}`);
  console.log(`Share links will use ${app.locals.baseUrl}`);
});
