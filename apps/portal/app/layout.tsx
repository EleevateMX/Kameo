import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'ALUX: El Despertar de Kukulkán',
  description: 'Aventura cooperativa 3D para 4 jugadores, en tu navegador. Explora los misterios de Yucatán junto a tus amigos.',
  icons: {
    icon: "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><path d='M32 4 6 34h52z' fill='%23c9944a'/><circle cx='32' cy='42' r='18' fill='%238c5b3c'/><circle cx='25' cy='42' r='5' fill='%235ff5e0'/><circle cx='39' cy='42' r='5' fill='%235ff5e0'/></svg>",
  },
};

export const viewport: Viewport = { themeColor: '#0b1512' };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link href="https://fonts.googleapis.com/css2?family=Bungee&family=Rubik:wght@400;500;600;700&display=swap" rel="stylesheet" />
      </head>
      <body>{children}</body>
    </html>
  );
}
