// The emulator: jsbeeb (https://github.com/mattgodbolt/jsbeeb), version 1.6.0,
// whose cycle-exact BBC Master model the harness runs headless (no window).
// It is taken from $JSBEEB (a jsbeeb checkout or package directory) if set,
// and otherwise from 6-harness/node_modules/jsbeeb ("npm install" here).
import { createRequire } from "module";
import { realpathSync } from "fs";
const dir = process.env.JSBEEB || decodeURIComponent(new URL("node_modules/jsbeeb", import.meta.url).pathname);
export const { MachineSession } = await import(`${dir}/src/machine-session.js`);
export const { BBC } = await import(`${dir}/src/utils.js`);
export const { toSsdOrDsd } = await import(`${dir}/src/disc.js`);
// sharp, the image library jsbeeb depends on (for tools that crop or write
// their own PNGs), as jsbeeb resolves it
export const sharp = (await import(createRequire(`${realpathSync(dir)}/package.json`).resolve("sharp"))).default;
