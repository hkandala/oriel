import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  async redirects() {
    return [
      { source: '/', destination: '/docs', permanent: false },
      // folders without an index page
      { source: '/docs/ui', destination: '/docs/ui/window', permanent: false },
      { source: '/docs/reference', destination: '/docs/reference/glossary', permanent: false },
    ];
  },
};

export default withMDX(config);
