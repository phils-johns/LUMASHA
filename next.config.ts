import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  output: 'standalone',
  compress: true,
  // La base SQLite locale (`data/lumasha.db`) ne doit JAMAIS être intégrée au
  // bundle standalone : elle est créée à l'exécution sur un volume persistant.
  // Sans cette exclusion, Next trace le fichier depuis `lib/server/db.ts` et
  // embarque la base de développement dans l'image de production.
  outputFileTracingExcludes: {
    '/*': ['./data/**/*', './*.db', './*.db-shm', './*.db-wal'],
  },
  images: {
    formats: ['image/webp'],
    minimumCacheTTL: 3600,
  },
  // Tailwind CSS v4 est compilé par Turbopack (voir @tailwindcss/turbopack).
  turbopack: {
    rules: {
      '*.css': {
        loaders: ['@tailwindcss/turbopack'],
        as: '*.css',
      },
    },
  },
  headers: async () => [
    {
      source: '/(.*)',
      headers: [
        { key: 'X-Frame-Options', value: 'DENY' },
        { key: 'X-Content-Type-Options', value: 'nosniff' },
        { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
      ],
    },
  ],
}

export default nextConfig
