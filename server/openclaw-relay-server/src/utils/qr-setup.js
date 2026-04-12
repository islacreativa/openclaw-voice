import qrcode from 'qrcode-terminal';
import { logger } from './logger.js';

export function showSetupQR(config) {
    const qrData = config.getQRData();
    const jsonStr = JSON.stringify(qrData);

    console.log('\n' + '='.repeat(60));
    console.log('  OpenClaw Voice — Connection Setup');
    console.log('='.repeat(60));
    console.log('\nScan this QR code with the OpenClaw Voice app:\n');

    qrcode.generate(jsonStr, { small: true }, (code) => {
        console.log(code);
    });

    console.log('\nOr enter manually:\n');
    console.log(`  URL:   ${qrData.url}`);
    if (qrData.tailscale_url) {
        console.log(`  Tailscale URL: ${qrData.tailscale_url}`);
    }
    console.log(`  Token: ${qrData.token}`);
    console.log('\n' + '='.repeat(60) + '\n');
}
