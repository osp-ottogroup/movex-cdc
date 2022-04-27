// use an alias for publicPath which should be replaced in built artifacts before production usage
// This way URLs with path may become usable like for nginx locations
module.exports = {
  publicPath: process.env.NODE_ENV === 'production' ? '/REPLACE_PUBLIC_PATH_BEFORE' : '',
};

