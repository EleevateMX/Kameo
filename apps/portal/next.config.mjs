import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

// Un solo archivo .env en la raíz del repositorio para todos los servicios
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
dotenv.config({ path: path.join(root, '.env') });

const API_URL = (process.env.API_URL || 'http://127.0.0.1:4000').replace(/\/$/, '');

/** @type {import('next').NextConfig} */
const nextConfig = {
  transpilePackages: ['@alux/shared-contracts'],
  poweredByHeader: false,
  devIndicators: false,
  turbopack: { root },
  // El navegador habla con la API a través del portal (mismo origen → la cookie de sesión viaja sola)
  async rewrites() {
    return [{ source: '/api/v1/:path*', destination: `${API_URL}/v1/:path*` }];
  },
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'X-Frame-Options', value: 'SAMEORIGIN' },
        ],
      },
    ];
  },
};

export default nextConfig;
