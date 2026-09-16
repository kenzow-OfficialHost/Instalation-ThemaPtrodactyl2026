#!/usr/bin/env node
/**
 * Patch webpack.config.js supaya build tema (khususnya Enigma) gak gagal
 * karena Webpack 5 udah gak auto-polyfill core module Node.js.
 *
 * Menambahkan:
 *  - require('webpack') di baris paling atas (kalau belum ada)
 *  - resolve.fallback untuk crypto, stream, vm
 *  - webpack.ProvidePlugin untuk Buffer & process
 *  - module.rules { fullySpecified: false } untuk .mjs — fix error
 *    "Can't resolve 'process/browser'" di framer-motion/axios/pathe
 *
 * Idempotent: aman dijalankan berkali-kali, gak akan dobel-nambahin.
 *
 * Usage: node patch-webpack-polyfills.js path/to/webpack.config.js
 */
const fs = require('fs');

const target = process.argv[2];
if (!target) {
  console.error('Usage: node patch-webpack-polyfills.js <webpack.config.js>');
  process.exit(1);
}

let content = fs.readFileSync(target, 'utf8');

if (!content.includes("require('webpack')") && !content.includes('require("webpack")')) {
  content = "const webpack = require('webpack');\n" + content;
}

if (content.includes('fallback:')) {
  if (!content.includes('crypto-browserify')) {
    content = content.replace(
      /fallback:\s*{/,
      "fallback: {\n      crypto: require.resolve('crypto-browserify'),\n      stream: require.resolve('stream-browserify'),"
    );
  }
  if (!content.includes('vm-browserify')) {
    content = content.replace(
      /fallback:\s*{/,
      "fallback: {\n      vm: require.resolve('vm-browserify'),"
    );
  }
} else if (content.includes('resolve:')) {
  content = content.replace(
    /resolve:\s*{/,
    "resolve: {\n    fallback: {\n      crypto: require.resolve('crypto-browserify'),\n      stream: require.resolve('stream-browserify'),\n      vm: require.resolve('vm-browserify'),\n    },"
  );
}

if (content.includes('plugins:') && !content.includes('ProvidePlugin')) {
  content = content.replace(
    /plugins:\s*\[/,
    "plugins: [\n    new webpack.ProvidePlugin({ Buffer: ['buffer', 'Buffer'], process: 'process/browser' }),"
  );
}

if (!content.includes('fullySpecified') && content.includes('rules:')) {
  content = content.replace(
    /rules:\s*\[/,
    "rules: [\n      { test: /\\.m?js$/, resolve: { fullySpecified: false } },"
  );
}

fs.writeFileSync(target, content);
console.log('webpack.config.js patched (crypto + vm + fullySpecified)');
