const { defineConfig } = require('@vue/cli-service');

module.exports = defineConfig({
  transpileDependencies: true,
  // use an alias for publicPath which should be replaced in built artifacts before production usage
  // This way URLs with path may become usable like for nginx locations
  publicPath: process.env.NODE_ENV === 'production' ? '/REPLACE_PUBLIC_PATH_BEFORE' : '',
});
