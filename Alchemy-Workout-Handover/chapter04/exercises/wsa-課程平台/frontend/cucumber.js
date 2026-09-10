process.env.TS_NODE_PROJECT = 'tsconfig.test.json';
process.env.TS_NODE_TRANSPILE_ONLY = 'true';

module.exports = {
  default: {
    requireModule: ['ts-node/register'],
    require: [
      'support/hooks.ts',
      'steps/**/*.steps.ts',
    ],
    paths: ['features/**/*.feature'],  // standard Cucumber path — includes pages/ AND journeys/
    format: ['progress', 'summary'],
    timeout: 30000,
  },
};
